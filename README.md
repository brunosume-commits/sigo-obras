# SIGO — Sistema Integrado de Gestão de Obras

Controle de materiais por canteiro, compras, custos, equipes e relatórios.
Os dados ficam num banco **Supabase** (PostgreSQL), então todos os usuários
veem as mesmas informações, de qualquer aparelho, atualizadas em tempo real.

## Perfis de acesso

| Perfil | Pode fazer |
|---|---|
| **Engenheiro** | Tudo, inclusive financeiro e liberação de usuários |
| **Almoxarife** | Entradas, saídas, transferências, estornos, materiais, fornecedores, compras e recebimentos |
| **Mestre de Obras** | Registrar saída de material, solicitar compras e marcar presença da equipe |

As permissões são aplicadas **no banco** (Row Level Security), não só na tela.

## Configuração (uma vez, cerca de 15 minutos)

### 1. Criar o projeto no Supabase
1. Acesse [supabase.com](https://supabase.com) e crie uma conta gratuita.
2. Clique em **New project**, dê o nome `sigo`, crie uma senha forte para o banco
   e escolha a região **South America (São Paulo)**.

### 2. Criar as tabelas
1. No menu lateral do projeto, abra **SQL Editor** → **New query**.
2. Cole todo o conteúdo de [`supabase/schema.sql`](supabase/schema.sql) e clique em **Run**.
   Depois, rode também [`supabase/migracao-002-presenca-categorias.sql`](supabase/migracao-002-presenca-categorias.sql).
   Depois, [`supabase/migracao-003-folha-pagamento.sql`](supabase/migracao-003-folha-pagamento.sql) , [`supabase/migracao-004-diario-obra.sql`](supabase/migracao-004-diario-obra.sql), [`supabase/migracao-005-documentos.sql`](supabase/migracao-005-documentos.sql) e [`supabase/migracao-006-epi.sql`](supabase/migracao-006-epi.sql).
3. (Opcional, só para testar) rode também [`supabase/dados-exemplo.sql`](supabase/dados-exemplo.sql).

### 3. Ajustar o login
Em **Authentication → URL Configuration**, coloque em **Site URL** o endereço
onde o SIGO está publicado (ex.: `https://brunosume-commits.github.io/sigo-obras/`).
Isso faz os links de confirmação e de troca de senha voltarem para o sistema.

### 4. Ligar o sistema ao banco
1. Em **Project Settings → API**, copie a **Project URL** e a chave **anon public**.
2. No `index.html`, preencha:
   ```js
   const SUPABASE_URL = 'https://xxxx.supabase.co';
   const SUPABASE_ANON_KEY = 'eyJhbGciOi...';
   ```
   A chave *anon* é pública por natureza; quem protege os dados são as regras do banco.
   **Nunca** coloque aqui a chave `service_role`.

### 5. Primeiro acesso
1. (Recomendado) No SQL Editor, cadastre o e-mail do administrador:
   `insert into public.administradores (email) values ('seu@email.com');`
   Sem isso, **a primeira conta criada vira Engenheiro** (administrador).
   Abra o sistema e clique em **Criar conta**.
2. Confirme pelo e-mail recebido e entre.
3. Para cada pessoa da equipe: ela clica em **Criar conta**; você abre a aba **Usuários**,
   escolhe o perfil e clica em **Liberar**. Contas novas não acessam nada até serem liberadas.

## Publicação
O sistema é um único `index.html`. Para publicar no GitHub Pages:
**Settings → Pages → Branch: main / (root) → Save**.

## Plano gratuito do Supabase
Atende bem o uso inicial (500 MB de banco). Projetos gratuitos sem nenhum acesso
por 7 dias são pausados (os dados não se perdem; basta reativar no painel).
