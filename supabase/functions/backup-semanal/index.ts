// SIGO — backup semanal (chamado pelo pg_cron todo domingo às 03:17 de Brasília).
// Exporta todas as tabelas (função exportar_backup), compacta (.json.gz), guarda no
// bucket privado "backups" (mantém os 12 últimos) e manda por e-mail aos administradores.
// Não devolve os dados na resposta. Roda no máximo uma vez a cada 6 dias, salvo
// chamada com a chave de serviço e ?forcar=1.

const URL_SB = Deno.env.get("SUPABASE_URL")!;
const CHAVE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const h = { apikey: CHAVE, Authorization: `Bearer ${CHAVE}`, "Content-Type": "application/json" };
const resp = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { "Content-Type": "application/json" } });

async function rest(caminho: string, init: RequestInit = {}) {
  const r = await fetch(`${URL_SB}${caminho}`, { ...init, headers: { ...h, ...(init.headers || {}) } });
  const t = await r.text();
  if (!r.ok) throw new Error(`${caminho}: ${r.status} ${t.slice(0, 300)}`);
  try { return t ? JSON.parse(t) : null; } catch { return t; }
}
const b64 = (u: Uint8Array) => { let s = ""; for (let i = 0; i < u.length; i += 0x8000) s += String.fromCharCode(...u.subarray(i, i + 0x8000)); return btoa(s); };

Deno.serve(async (req) => {
  const servico = (req.headers.get("Authorization") || "") === `Bearer ${CHAVE}`;
  const forcar = servico && new URL(req.url).searchParams.get("forcar") === "1";
  try {
    const ult = await rest(`/rest/v1/backups?erro=is.null&order=feito_em.desc&limit=1&select=feito_em`);
    if (!forcar && ult?.length && Date.now() - new Date(ult[0].feito_em).getTime() < 6 * 86400000) return resp({ ok: true, ja_feito: ult[0].feito_em });

    const dados = await rest(`/rest/v1/rpc/exportar_backup`, { method: "POST", body: "{}" });
    const linhas = Object.values(dados.tabelas || {}).reduce((s: number, v: any) => s + (Array.isArray(v) ? v.length : 0), 0);
    const texto = new TextEncoder().encode(JSON.stringify(dados));
    const gz = new Uint8Array(await new Response(new Blob([texto]).stream().pipeThrough(new CompressionStream("gzip"))).arrayBuffer());
    const dia = new Date(Date.now() - 3 * 3600000).toISOString().slice(0, 10);
    const nome = `sigo-backup-${dia}.json.gz`;

    // guarda no Storage
    const up = await fetch(`${URL_SB}/storage/v1/object/backups/${nome}`, { method: "POST", headers: { apikey: CHAVE, Authorization: `Bearer ${CHAVE}`, "Content-Type": "application/gzip", "x-upsert": "true" }, body: gz });
    if (!up.ok) throw new Error(`storage: ${up.status} ${await up.text()}`);
    // mantém os 12 mais recentes
    const lista = await rest(`/storage/v1/object/list/backups`, { method: "POST", body: JSON.stringify({ prefix: "", limit: 200, sortBy: { column: "name", order: "desc" } }) });
    const velhos = (lista || []).map((o: any) => o.name).filter((n: string) => n.startsWith("sigo-backup-")).slice(12);
    if (velhos.length) await rest(`/storage/v1/object/backups`, { method: "DELETE", body: JSON.stringify({ prefixes: velhos }) });

    // e-mail com o arquivo anexo
    let para: string[] = [], erroEmail: string | null = null;
    const KEY = Deno.env.get("RESEND_API_KEY");
    if (KEY) {
      para = (Deno.env.get("ALERTAS_PARA") || "").split(",").map((s) => s.trim()).filter(Boolean);
      if (!para.length) para = await rest(`/rest/v1/rpc/emails_administradores`, { method: "POST", body: "{}" });
      const de = Deno.env.get("ALERTAS_REMETENTE") || "SIGO <onboarding@resend.dev>";
      const enviados: string[] = [];
      for (const dest of para) {
        const r = await fetch("https://api.resend.com/emails", {
          method: "POST", headers: { Authorization: `Bearer ${KEY}`, "Content-Type": "application/json" },
          body: JSON.stringify({
            from: de, to: [dest], subject: `SIGO — backup semanal ${dia.split("-").reverse().join("/")}`,
            html: `<p>Segue o backup semanal do SIGO (${linhas.toLocaleString("pt-BR")} registros, ${(gz.length / 1024).toFixed(0)} KB compactado).</p><p>Guarde este e-mail: o arquivo anexo permite recuperar os dados se algo der errado. Uma cópia também fica no Supabase (Storage → backups, últimas 12 semanas). As fotos e anexos não entram no arquivo.</p>`,
            attachments: [{ filename: nome, content: b64(gz) }],
          }),
        });
        if (r.ok) enviados.push(dest); else erroEmail = `${dest}: ${r.status} ${(await r.text()).slice(0, 200)}`;
      }
      para = enviados;
    } else erroEmail = "RESEND_API_KEY não configurada (backup só no Storage).";

    await rest(`/rest/v1/backups`, { method: "POST", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ arquivo: nome, bytes: gz.length, linhas, enviado_para: para, erro: null }) });
    return resp({ ok: true, arquivo: nome, bytes: gz.length, linhas, enviado_para: para, aviso_email: erroEmail });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    try { await rest(`/rest/v1/backups`, { method: "POST", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ erro: msg.slice(0, 500) }) }); } catch { /* ignora */ }
    return resp({ ok: false, erro: msg }, 500);
  }
});
