# ECS v2 conventions

- Define components once and reuse their handles.
- Put frequently queried state in dense components; use sparse storage for
  independently changing statuses.
- Cache stable hot queries. Do not cache sparse queries.
- Treat tags as membership only; never attach data to a tag.
- Destroy compiled queries and worlds that are no longer owned.
- Use relation cleanup traits deliberately. `ChildOf` deletes descendants by
  default; most other target deletion removes the pair.
- Keep gameplay authority outside presentation code. ECS storage does not make
  client-authored state trustworthy.
- Prefer systems with narrow queries and deterministic phase/priority ordering.
