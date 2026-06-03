# Retention & lifecycle

## Loki

- Configure retention in Loki compactor.
- Configure bucket lifecycle policies in object storage as a safety net.

## Tempo

- Configure block retention and compaction.
- Configure bucket lifecycle policies.

## Thanos (optional)

- Configure retention on compactor.
- Configure bucket lifecycle policies.

## Recommendation

Treat object storage lifecycle rules as your last-resort guardrail.
The primary retention policy should be configured in the application (Loki/Tempo/Thanos)
so queries and metadata remain consistent.
