-- Esquema inicial de TCG - Partner en Supabase.
--
-- Cada tabla refleja un JSON de ~/Library/Application Support/TCGPartner/ con estas columnas comunes:
--   id                 el mismo UUID que usa la app (lo genera el cliente)
--   user_id            dueño de la fila; por defecto, el usuario que inicia sesión
--   updated_at         último cambio según el equipo que lo hizo (`updatedAt` en Swift).
--                      Si dos equipos cambian la misma fila, gana el más reciente (ver keep_newest()).
--   deleted_at         borrado lógico: la fila se conserva para que el borrado llegue a los otros equipos
--   server_updated_at  la pone el servidor en cada escritura; los clientes piden "lo que cambió desde X"
--                      con esta columna, porque el reloj de cada equipo puede ir adelantado o atrasado
--
-- Sin llaves foráneas entre tablas de la app (deck_id, archetype_id…): los equipos suben las filas en
-- cualquier orden y sin conexión, y la app ya tolera referencias a elementos que no existen.
--
-- Los enums se guardan como texto con CHECK. Si se añade un caso en Swift, hay que añadirlo aquí
-- con una migración nueva.

-- ─── Funciones comunes ──────────────────────────────────────────────────────────────────────────

-- Marca server_updated_at en cada inserción o actualización.
create or replace function public.touch_server_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.server_updated_at := now();
  return new;
end;
$$;

-- Gana el cambio más reciente: si llega una versión más vieja que la guardada, se ignora.
-- Así un equipo que estuvo sin conexión no pisa lo que otro cambió después.
create or replace function public.keep_newest()
returns trigger
language plpgsql
as $$
begin
  if new.updated_at < old.updated_at then
    return null;
  end if;
  return new;
end;
$$;

-- Aplica columnas comunes, triggers, índice y permisos por usuario a una tabla.
create or replace function public.setup_synced_table(t regclass)
returns void
language plpgsql
as $$
begin
  execute format('create index on %s (user_id, server_updated_at)', t);
  execute format('create trigger keep_newest before update on %s for each row execute function public.keep_newest()', t);
  execute format('create trigger touch_server_updated_at before insert or update on %s for each row execute function public.touch_server_updated_at()', t);
  execute format('alter table %s enable row level security', t);
  -- Cada usuario solo ve y cambia sus filas. No hay política de DELETE: se borra con deleted_at.
  execute format('create policy "select own" on %s for select to authenticated using ((select auth.uid()) = user_id)', t);
  execute format('create policy "insert own" on %s for insert to authenticated with check ((select auth.uid()) = user_id)', t);
  execute format('create policy "update own" on %s for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id)', t);
end;
$$;

-- ─── Tablas ─────────────────────────────────────────────────────────────────────────────────────

-- Decks/<uuid>.json
create table public.decks (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name              text not null,
  -- El texto de la lista es la fuente de verdad; las cartas se vuelven a leer con DeckParser.
  list              text not null,
  notes             text not null default '',
  -- Nombre de la carpeta (como en la app); null = suelto.
  folder            text,
  archetype_id      uuid,
  status            text check (status in ('ready', 'testing', 'idea', 'retired')),
  icons             text[],
  created           timestamptz not null,
  modified          timestamptz not null,
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz,
  server_updated_at timestamptz not null default now()
);

-- folders.json (una fila por carpeta; el id se conserva al renombrarla)
create table public.folders (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name              text not null,
  archetype_id      uuid,
  icons             text[],
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz,
  server_updated_at timestamptz not null default now()
);

-- archetypes.json
create table public.archetypes (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name              text not null,
  color             text not null default 'blue'
                    check (color in ('blue', 'purple', 'pink', 'red', 'orange', 'yellow', 'green', 'teal')),
  -- null = los iconos se deducen del nombre.
  icons             text[],
  notes             text not null default '',
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz,
  server_updated_at timestamptz not null default now()
);

-- events.json
create table public.events (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name              text not null default '',
  kind              text not null default 'cup'
                    check (kind in ('league', 'challenge', 'cup', 'regional', 'special', 'international', 'worlds', 'online', 'other')),
  start_date        timestamptz not null,
  end_date          timestamptz,
  location          text not null default '',
  link              text not null default '',
  cost              double precision,
  currency          text not null default 'MXN',
  format            text not null default 'standard' check (format in ('standard', 'expanded')),
  planned_deck_id   uuid,
  registered        boolean not null default false,
  placement         integer,
  players           integer,
  notes             text not null default '',
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz,
  server_updated_at timestamptz not null default now()
);

-- matches.json
create table public.matches (
  id                 uuid primary key,
  user_id            uuid not null default auth.uid() references auth.users (id) on delete cascade,
  date               timestamptz not null,
  deck_id            uuid,
  result             text not null check (result in ('win', 'loss', 'tie')),
  opponent           text not null default '',
  opponent_archetype text not null default '',
  event_id           uuid,
  notes              text not null default '',
  -- null en partidas anteriores a que existiera el tipo (la app las trata como presenciales).
  kind               text check (kind in ('online', 'inPerson')),
  battle_log         text,
  went_first         boolean,
  turns              integer,
  my_prizes          integer,
  opponent_prizes    integer,
  round              text,
  updated_at         timestamptz not null default now(),
  deleted_at         timestamptz,
  server_updated_at  timestamptz not null default now()
);

-- journal.json
create table public.journal_entries (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  archetype_id      uuid not null,
  kind              text not null default 'note' check (kind in ('lesson', 'guide', 'note')),
  title             text not null default '',
  body              text not null default '',
  opponent          text not null default '',
  match_id          uuid,
  pinned            boolean not null default false,
  created           timestamptz not null,
  modified          timestamptz not null,
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz,
  server_updated_at timestamptz not null default now()
);

-- players.json
create table public.players (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name              text not null default '',
  -- Play! Pokémon ID (texto: puede tener ceros a la izquierda).
  player_id         text not null default '',
  -- timestamptz y no date, para que vuelva exactamente igual a la app.
  birth_date        timestamptz,
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz,
  server_updated_at timestamptz not null default now()
);

select public.setup_synced_table(t)
from unnest(array[
  'public.decks', 'public.folders', 'public.archetypes', 'public.events',
  'public.matches', 'public.journal_entries', 'public.players'
]::regclass[]) as t;

drop function public.setup_synced_table(regclass);
