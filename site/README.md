# Daily activity on the project page

The English and Chinese homepages show daily activity, a 7/30-day trend, and Android/iOS/HarmonyOS totals. All dates use Asia/Shanghai. The current day is a partial value as of the displayed timestamp. Reporting starts with the first recorded day; earlier history is not invented. The public file contains aggregate counts only, without daily identifiers, accounts, books, or per-version details.

## Refresh the static snapshot

The **Publish project page** workflow runs about hourly and can be started manually from Actions. It fetches a fixed, read-only aggregate using the repository secret `ACTIVITY_EXPORT_TOKEN`, validates the exact response fields, builds the site, and deploys a Pages artifact. It does not commit hourly data or give the workflow repository-write permissions.

The browser fetches only `activity.json` on GitHub Pages. It never calls the Worker or receives an export credential. The authenticated export reuses the existing client-check path and limiter; it does not reopen a mirror route or expose a SQL query interface.

If fetching or validation fails, the workflow stops before deployment, leaving the previous site online. The site shows its snapshot timestamp and marks data older than three hours as stale. GitHub may delay scheduled jobs, and public-repository schedules can be disabled after 60 days without repository activity; use Actions to re-enable the workflow and run a manual refresh when needed. See [GitHub's scheduled workflow guidance](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule).

For a local build with current aggregate data:

```sh
# Provide the export credential through the process environment, never source files.
python3 tools/fetch_activity_snapshot.py --output build/activity-snapshot.json
python3 tools/build_project_site.py --activity-snapshot build/activity-snapshot.json
```

The original `python3 tools/build_project_site.py` entry point also works without credentials; activity is shown as unavailable rather than fabricated zeroes. Do not publish that data-free preview over the scheduled production build.

To rotate the read-only export credential, update the Worker secret and the matching repository secret together, then run a manual workflow. Keep the last working Worker version for rollback. Never place credentials in the template, JavaScript, snapshot, logs, or Git history.
