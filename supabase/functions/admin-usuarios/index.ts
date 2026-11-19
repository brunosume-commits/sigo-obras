// SIGO — gestão de usuários pelos administradores (aba Usuários).
// Só quem está na tabela administradores (função sou_administrador) consegue usar.
// Ações (POST JSON):
//   { acao: "criar",  nome, email, senha, perfil, obras?: uuid[] }
//   { acao: "editar", id, nome, email, perfil, ativo, obras?: uuid[] }
//   { acao: "senha",  id, senha }
// Senhas não são lidas nem guardadas aqui: vão direto para o Supabase Auth.

const URL_SB = Deno.env.get("SUPABASE_URL")!;
const SERVICO = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const PERFIS = ["Engenheiro", "Almoxarife", "Mestre de Obras", "Cliente"];
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const resp = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { ...cors, "Content-Type": "application/json" } });
const hs = { apikey: SERVICO, Authorization: `Bearer ${SERVICO}`, "Content-Type": "application/json" };

async function chamar(caminho: string, metodo: string, corpo?: unknown, extra: Record<string, string> = {}) {
  const r = await fetch(`${URL_SB}${caminho}`, { method: metodo, headers: { ...hs, ...extra }, body: corpo === undefined ? undefined : JSON.stringify(corpo) });
  const txt = await r.text();
  let dados: any = null; try { dados = txt ? JSON.parse(txt) : null; } catch { dados = txt; }
  if (!r.ok) {
    const msg = dados?.msg || dados?.message || dados?.error_description || dados?.error || txt;
    throw new Error(/already been registered|already registered|email_exists/i.test(String(msg)) ? "Já existe um usuário com este e-mail." : String(msg));
  }
  return dados;
}
const emailOk = (e: string) => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(e);

async function definirObras(id: string, perfil: string, obras: unknown) {
  await chamar(`/rest/v1/cliente_obras?perfil_id=eq.${id}`, "DELETE");
  const lista = perfil === "Cliente" && Array.isArray(obras) ? obras.filter((x) => typeof x === "string") : [];
  if (lista.length) await chamar(`/rest/v1/cliente_obras`, "POST", lista.map((o) => ({ perfil_id: id, obra_id: o })), { Prefer: "return=minimal" });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const auth = req.headers.get("Authorization") || "";
    // Quem chamou é administrador? (consulta feita com o token da própria pessoa)
    const adm = await fetch(`${URL_SB}/rest/v1/rpc/sou_administrador`, { method: "POST", headers: { apikey: ANON, Authorization: auth, "Content-Type": "application/json" }, body: "{}" });
    if (!adm.ok || (await adm.json()) !== true) return resp({ erro: "Só os administradores podem gerenciar usuários." }, 403);
    const eu = await fetch(`${URL_SB}/auth/v1/user`, { headers: { apikey: ANON, Authorization: auth } }).then((r) => r.json());

    const b = await req.json();
    const acao = b.acao;
    if (acao === "criar") {
      const nome = String(b.nome || "").trim(), email = String(b.email || "").trim().toLowerCase(), senha = String(b.senha || ""), perfil = String(b.perfil || "");
      if (!nome) return resp({ erro: "Informe o nome." }, 400);
      if (!emailOk(email)) return resp({ erro: "E-mail inválido." }, 400);
      if (senha.length < 8) return resp({ erro: "A senha precisa ter pelo menos 8 caracteres." }, 400);
      if (!PERFIS.includes(perfil)) return resp({ erro: "Perfil inválido." }, 400);
      const u = await chamar(`/auth/v1/admin/users`, "POST", { email, password: senha, email_confirm: true, user_metadata: { nome } });
      const id = u.id || u.user?.id;
      await chamar(`/rest/v1/perfis?id=eq.${id}`, "PATCH", { nome, email, perfil, ativo: true }, { Prefer: "return=minimal" });
      await definirObras(id, perfil, b.obras);
      return resp({ ok: true, id });
    }
    if (acao === "editar") {
      const id = String(b.id || ""), nome = String(b.nome || "").trim(), email = String(b.email || "").trim().toLowerCase(), perfil = String(b.perfil || ""), ativo = !!b.ativo;
      if (!id) return resp({ erro: "Usuário não informado." }, 400);
      if (!nome) return resp({ erro: "Informe o nome." }, 400);
      if (!emailOk(email)) return resp({ erro: "E-mail inválido." }, 400);
      if (!PERFIS.includes(perfil)) return resp({ erro: "Perfil inválido." }, 400);
      if (id === eu?.id && (!ativo || perfil !== "Engenheiro")) return resp({ erro: "Você não pode desativar a sua própria conta nem tirar o seu perfil de Engenheiro." }, 400);
      const atual = await chamar(`/rest/v1/perfis?id=eq.${id}&select=email`, "GET");
      if (!atual?.length) return resp({ erro: "Usuário não encontrado." }, 404);
      if ((atual[0].email || "").toLowerCase() !== email) await chamar(`/auth/v1/admin/users/${id}`, "PUT", { email, email_confirm: true });
      await chamar(`/auth/v1/admin/users/${id}`, "PUT", { user_metadata: { nome } });
      await chamar(`/rest/v1/perfis?id=eq.${id}`, "PATCH", { nome, email, perfil, ativo }, { Prefer: "return=minimal" });
      await definirObras(id, perfil, b.obras);
      return resp({ ok: true });
    }
    if (acao === "senha") {
      const id = String(b.id || ""), senha = String(b.senha || "");
      if (!id) return resp({ erro: "Usuário não informado." }, 400);
      if (senha.length < 8) return resp({ erro: "A senha precisa ter pelo menos 8 caracteres." }, 400);
      await chamar(`/auth/v1/admin/users/${id}`, "PUT", { password: senha });
      return resp({ ok: true });
    }
    return resp({ erro: "Ação desconhecida." }, 400);
  } catch (e) {
    return resp({ erro: e instanceof Error ? e.message : String(e) }, 500);
  }
});
