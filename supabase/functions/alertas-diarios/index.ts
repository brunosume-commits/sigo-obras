// SIGO — e-mail diário com o que precisa de atenção.
// Chamada pelo agendador (pg_cron) todo dia às 06:47 (horário de Brasília).
// Segredos (Supabase → Edge Functions → Secrets):
//   RESEND_API_KEY     chave da conta gratuita em resend.com (obrigatório)
//   ALERTAS_PARA       opcional: e-mails separados por vírgula (padrão: administradores do SIGO)
//   ALERTAS_REMETENTE  opcional: ex. "SIGO <avisos@suaempresa.com.br>" (padrão: onboarding@resend.dev)
// Parâmetros: ?teste=1 mostra o resumo sem enviar · ?forcar=1 envia de novo no mesmo dia.

const URL_SB = Deno.env.get("SUPABASE_URL")!;
const CHAVE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SITE = "https://brunosume-commits.github.io/sigo-obras/";
const h = { apikey: CHAVE, Authorization: `Bearer ${CHAVE}`, "Content-Type": "application/json" };

const rpc = async (fn: string, args = {}) => {
  const r = await fetch(`${URL_SB}/rest/v1/rpc/${fn}`, { method: "POST", headers: h, body: JSON.stringify(args) });
  if (!r.ok) throw new Error(`${fn}: ${r.status} ${await r.text()}`);
  return r.json();
};
const esc = (s: string) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]!));
const resp = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  try {
    const u = new URL(req.url);
    const teste = u.searchParams.get("teste") === "1", forcar = u.searchParams.get("forcar") === "1";
    const resumo = await rpc("resumo_alertas");
    const itens: { grupo: string; grav: string; texto: string }[] = resumo.itens || [];
    if (teste) return resp({ ok: true, teste: true, resumo });

    const ja = await fetch(`${URL_SB}/rest/v1/envios_alertas?dia=eq.${resumo.dia}&erro=is.null&select=dia`, { headers: h }).then((r) => r.json());
    if (ja.length && !forcar) return resp({ ok: true, ja_enviado_hoje: true });
    if (!itens.length) return resp({ ok: true, nada_a_avisar: true });

    const KEY = Deno.env.get("RESEND_API_KEY");
    if (!KEY) return resp({ ok: false, erro: "Falta configurar o segredo RESEND_API_KEY." });
    const para: string[] = (Deno.env.get("ALERTAS_PARA") || "").split(",").map((s) => s.trim()).filter(Boolean);
    if (!para.length) para.push(...(await rpc("emails_administradores")));
    const de = Deno.env.get("ALERTAS_REMETENTE") || "SIGO <onboarding@resend.dev>";

    const cor: Record<string, string> = { alta: "#b91c1c", media: "#b45309", baixa: "#334155" };
    const grupos = [...new Set(itens.map((i) => i.grupo))];
    const altas = itens.filter((i) => i.grav === "alta").length;
    const [a, m, d] = String(resumo.dia).split("-");
    const html = `<div style="font-family:Arial,sans-serif;max-width:640px;color:#0f172a">
      <div style="background:#0f172a;color:#fff;padding:16px 20px;border-radius:12px 12px 0 0">
        <div style="font-size:12px;letter-spacing:2px;color:#f59e0b;font-weight:bold">SIGO · AVISOS DO DIA</div>
        <div style="font-size:20px;font-weight:bold;margin-top:4px">${d}/${m}/${a} — ${itens.length} ponto(s) de atenção${altas ? `, ${altas} urgente(s)` : ""}</div>
      </div>
      <div style="border:1px solid #e2e8f0;border-top:0;padding:8px 20px 20px;border-radius:0 0 12px 12px">
      ${grupos.map((g) => `<h3 style="font-size:15px;margin:18px 0 6px">${esc(g)}</h3><ul style="margin:0;padding-left:18px">${
        itens.filter((i) => i.grupo === g).map((i) => `<li style="margin:3px 0;color:${cor[i.grav] || "#334155"}">${esc(i.texto)}</li>`).join("")}</ul>`).join("")}
      <p style="margin-top:22px"><a href="${SITE}" style="background:#f59e0b;color:#0f172a;padding:10px 16px;border-radius:8px;text-decoration:none;font-weight:bold">Abrir o SIGO</a></p>
      <p style="font-size:11px;color:#64748b;margin-top:16px">Saldo do caixa hoje: R$ ${Number(resumo.saldo_caixa || 0).toLocaleString("pt-BR", { minimumFractionDigits: 2 })}. E-mail automático do SIGO, enviado todo dia às 6h47.</p>
      </div></div>`;
    const texto = itens.map((i) => `[${i.grupo}] ${i.texto}`).join("\n") + `\n\n${SITE}`;

    const erros: string[] = [], ok: string[] = [];
    for (const to of para) {
      const r = await fetch("https://api.resend.com/emails", {
        method: "POST", headers: { Authorization: `Bearer ${KEY}`, "Content-Type": "application/json" },
        body: JSON.stringify({ from: de, to: [to], subject: `SIGO — ${itens.length} aviso(s) hoje${altas ? ` (${altas} urgente)` : ""}`, html, text: texto }),
      });
      if (r.ok) ok.push(to); else erros.push(`${to}: ${r.status} ${(await r.text()).slice(0, 200)}`);
    }
    await fetch(`${URL_SB}/rest/v1/envios_alertas?on_conflict=dia`, {
      method: "POST", headers: { ...h, Prefer: "resolution=merge-duplicates" },
      body: JSON.stringify({ dia: resumo.dia, enviado_em: new Date().toISOString(), destinatarios: ok, itens: itens.length, erro: erros.length ? erros.join(" | ") : null }),
    });
    return resp({ ok: !erros.length || ok.length > 0, enviados: ok, erros });
  } catch (e) {
    return resp({ ok: false, erro: String(e) }, 500);
  }
});
