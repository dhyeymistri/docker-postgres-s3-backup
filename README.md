# Zero-Friction Postgres → S3/R2 Backup Sidecar

> 💡 **Looking for a ready-to-deploy, turnkey appliance?**  
> Download the pre-packaged bundle with zero-disk streaming and multi-storage configs on [Gumroad](https://mistral117.gumroad.com/l/postgres-s3-backup-docker).

A self-contained Docker sidecar that takes compressed daily snapshots of a
PostgreSQL database, ships them to any S3-compatible storage (Cloudflare R2,
AWS S3, MinIO, Wasabi, Backblaze B2), and prunes archives past a retention
window — no host cron jobs, no local AWS credentials on the VPS itself.

## Prerequisites

- Docker + Docker Compose v2

## Quickstart

```bash
cp .env.example .env
# edit .env with your DB and S3/R2 credentials
docker compose up -d --build
```

To attach this to an **existing** Postgres container instead of the example
one included here: delete the `postgres` service from `docker-compose.yml`,
point `PGHOST` in `.env` at your existing service name, and put
`backup-runner` on the same Docker network as that service.

## How it works

- `backup-runner` builds from a small Alpine image with `pg_dump`, `aws-cli`,
  and `dcron` baked in (no runtime `apk add`, so restarts don't depend on a
  package mirror being reachable).
- `entrypoint.sh` snapshots the container's env into `/etc/backup.env` and
  installs the cron schedule, then runs `crond` in the foreground as PID 1.
- `backup.sh` runs on that schedule: dumps the DB to a temp file, checks
  `pg_dump`'s exit code and file size directly (rather than trusting a piped
  command's exit status), gzips it, uploads to your S3/R2 bucket, then
  deletes objects older than `RETENTION_DAYS` using epoch-based comparison.
- Logs are written to `/var/log/backup.log` inside the container and
  streamed to `docker compose logs -f backup-runner`.

## Verify it's working

```bash
docker compose logs -f backup-runner
docker compose exec backup-runner aws --endpoint-url=$S3_ENDPOINT s3 ls s3://$S3_BUCKET/
```

## Notes

- Scope your R2/S3 API token to this bucket only — don't use full-account keys.
- `RETENTION_DAYS` deletion is best-effort per run; it doesn't use bucket
  lifecycle policies, so if the container is down past your retention window,
  cleanup simply resumes on the next successful run.
# docker-postgres-s3-backup
