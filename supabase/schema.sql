-- ForexEA signal app schema. Run once in Supabase: Dashboard -> SQL Editor -> New query -> paste -> Run.
-- Reads: anyone holding the anon key (the app). Writes: only the MT5 Signal Engine using the
-- service_role key, which bypasses RLS. Never put the service_role key in the app or the repo.

create table if not exists public.market (
  symbol        text primary key,
  bid           numeric not null,
  ask           numeric not null,
  regime        text,                 -- e.g. TRENDING_UP, RANGING, HIGH_VOL
  regime_detail jsonb,                -- indicator values behind the regime call
  updated_at    timestamptz not null default now()
);

create table if not exists public.signals (
  id            bigint generated always as identity primary key,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  symbol        text not null default 'XAUUSD',
  strategy      text not null,        -- e.g. LONDON_BREAKOUT
  regime        text,
  status        text not null,        -- PENDING, ACTIVE, TP1, TP2, CLOSED_TP, CLOSED_SL, CLOSED_BE, ESCAPED, CANCELLED, NO_TRADE
  side          text,                 -- BUY, SELL, or null while both pending orders wait
  buy_entry     numeric,
  sell_entry    numeric,
  entry         numeric,              -- filled side's entry once ACTIVE
  sl            numeric,
  tp1           numeric,
  tp2           numeric,
  tp3           numeric,
  lots          numeric,
  risk_usd      numeric,              -- loss at SL for the suggested lot size
  running_pips  numeric,
  peak_pips     numeric,
  result_pips   numeric,
  reasons       jsonb,                -- list of strings shown as SIGNAL REASON
  stats         jsonb,                -- historical win rate / PF for this setup type
  escape        jsonb,                -- escape rule state and advice text
  news_risk     text                  -- LOW, MEDIUM, HIGH
);
create index if not exists signals_created_idx on public.signals (created_at desc);

create table if not exists public.news_briefs (
  id          bigint generated always as identity primary key,
  created_at  timestamptz not null default now(),
  brief_date  date not null unique,
  risk_level  text not null,          -- LOW, MEDIUM, HIGH
  events      jsonb,                  -- [{time, title, impact}]
  summary     text
);

alter table public.market      enable row level security;
alter table public.signals     enable row level security;
alter table public.news_briefs enable row level security;

drop policy if exists "read market" on public.market;
drop policy if exists "read signals" on public.signals;
drop policy if exists "read news" on public.news_briefs;
create policy "read market"  on public.market      for select using (true);
create policy "read signals" on public.signals     for select using (true);
create policy "read news"    on public.news_briefs for select using (true);
