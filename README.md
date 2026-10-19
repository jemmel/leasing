# Leasing-Kilometerrechner

Zeigt, ob der Kilometerstand im Leasing-Plan liegt: Soll, Abweichung, Rest-km und Prognose zum
Vertragsende. Installierbar als Web-App (Manifest und Service Worker), ohne Abhängigkeiten. Die
Eingaben bleiben im Browser.

Online: https://leasing.janemmel.de (Cloudflare Pages, Projekt `leasing-janemmel-de`).
Vorher unter https://leasing.freizeitkamele.de.

```powershell
./deploy.ps1 -DryRun   # _site/ bauen (index.html, manifest.json, service-worker.js, _headers)
./deploy.ps1           # hochladen; legt beim ersten Mal Projekt, Domain und CNAME an
```

Cloudflare-Token: `$env:CLOUDFLARE_API_TOKEN` oder `cloudflare_api_token=...` in `.env` (nicht im Repo).

Der Service Worker liefert alles aus dem Cache (`CACHE_NAME` in `service-worker.js`). Nach Änderungen an
`index.html` den Namen hochzählen, sonst sehen installierte Apps die neue Version nicht.
