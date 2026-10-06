-- Casa em dia: configuração do banco (rodar uma vez só)

-- 1) Quem pode entrar e quem é quem
create table public.membros (
  email text primary key,
  pessoa text not null check (pessoa in ('alexandre', 'ana'))
);
insert into public.membros (email, pessoa) values
  ('xandidp@gmail.com', 'alexandre'),
  ('(email da Ana)', 'ana');

-- 2) Dados da casa
create table public.estado (
  id int primary key check (id = 1),
  entries jsonb not null default '[]'::jsonb,
  revision int not null default 0,
  updated_at timestamptz not null default now(),
  updated_by text
);
insert into public.estado (id) values (1);

-- 3) Cópia automática de cada versão anterior (para desfazer erros)
create table public.estado_historico (
  id bigint generated always as identity primary key,
  entries jsonb not null,
  revision int not null,
  updated_at timestamptz,
  updated_by text,
  saved_at timestamptz not null default now()
);

create function public.guardar_historico() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.estado_historico (entries, revision, updated_at, updated_by)
  values (old.entries, old.revision, old.updated_at, old.updated_by);
  return new;
end $$;

create trigger estado_historico_trg before update on public.estado
  for each row execute function public.guardar_historico();

-- 4) Segurança: só quem está em "membros" lê e grava
create function public.eh_membro() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.membros
    where lower(email) = lower(auth.jwt() ->> 'email')
  )
$$;

alter table public.membros enable row level security;
alter table public.estado enable row level security;
alter table public.estado_historico enable row level security;

create policy "ver o proprio cadastro" on public.membros
  for select to authenticated
  using (lower(email) = lower(auth.jwt() ->> 'email'));

create policy "membros leem" on public.estado
  for select to authenticated using (public.eh_membro());

create policy "membros salvam" on public.estado
  for update to authenticated
  using (public.eh_membro()) with check (public.eh_membro() and id = 1);

create policy "membros leem historico" on public.estado_historico
  for select to authenticated using (public.eh_membro());

revoke all on public.membros, public.estado, public.estado_historico from anon, authenticated;
grant select on public.membros to authenticated;
grant select on public.estado to authenticated;
grant update (entries, revision, updated_at, updated_by) on public.estado to authenticated;
grant select on public.estado_historico to authenticated;
revoke execute on function public.guardar_historico() from public, anon, authenticated;
