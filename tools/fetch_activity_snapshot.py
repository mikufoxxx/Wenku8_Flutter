#!/usr/bin/env python3
"""Fetch only the approved aggregate snapshot for a static Pages deployment."""
import argparse
from datetime import date, datetime, timedelta, timezone
import json
import os
import time
from pathlib import Path
from urllib.request import Request, HTTPRedirectHandler, build_opener
from urllib.error import HTTPError, URLError


def validate_snapshot(data):
    if not isinstance(data, dict) or set(data) != {'schema', 'timezone', 'asOf', 'firstDay', 'days'} or data['schema'] != 1 or data['timezone'] != 'Asia/Shanghai':
        raise ValueError('Unexpected activity snapshot fields')
    stamp = datetime.fromisoformat(data['asOf'].replace('Z', '+00:00'))
    if stamp.tzinfo is None:
        raise ValueError('Snapshot timestamp requires a timezone')
    today = stamp.astimezone(timezone(timedelta(hours=8))).date()
    first = date.fromisoformat(data['firstDay']) if data['firstDay'] is not None else None
    if not isinstance(data['days'], list) or len(data['days']) > 30:
        raise ValueError('Invalid snapshot range')
    previous = None
    for row in data['days']:
        if not isinstance(row, dict) or set(row) != {'day', 'active', 'android', 'ios', 'harmony', 'capped'}:
            raise ValueError('Unexpected daily fields')
        current = date.fromisoformat(row['day'])
        if current > today or current < today - timedelta(days=29) or previous and current != previous + timedelta(days=1):
            raise ValueError('Invalid daily calendar')
        if type(row['capped']) is not bool or any(type(row[key]) is not int or not 0 <= row[key] <= 10000 for key in ['active', 'android', 'ios', 'harmony']):
            raise ValueError('Invalid daily values')
        if row['active'] != sum(row[key] for key in ['android', 'ios', 'harmony']):
            raise ValueError('Platform totals do not match')
        previous = current
    if data['days'] and (first is None or first > date.fromisoformat(data['days'][0]['day']) or previous != today):
        raise ValueError('Incomplete snapshot')
    return data


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    token = os.environ.get('ACTIVITY_EXPORT_TOKEN')
    if not token:
        raise SystemExit('Configure the aggregate export credential before publishing activity data.')
    request = Request('https://app.3952039.xyz/client/check', method='POST',
                      data=b'{"schema":1,"mode":"activity-snapshot"}',
                      headers={'Authorization': f'Bearer {token}', 'X-Activity-Snapshot': '1',
                               'Content-Type': 'application/json', 'User-Agent': 'Wenku8-Activity-Snapshot/1'})
    # Never forward the credential to a redirect target or write it into an asset.
    for attempt in range(3):
        try:
            with build_opener(NoRedirect).open(request, timeout=30) as response:
                payload = response.read(32769)
                if response.status != 200 or len(payload) > 32768:
                    raise ValueError('Invalid snapshot response')
            break
        except HTTPError as error:
            detail = error.read(512).decode('utf-8', errors='replace').replace(token, '[redacted]')
            if error.code not in {429, 502, 503, 504} or attempt == 2:
                raise SystemExit(f'Activity export HTTP {error.code}: {detail}') from None
        except URLError:
            if attempt == 2:
                raise SystemExit('Activity export connection failed; previous Pages deployment is preserved.') from None
        time.sleep(2 ** attempt)
    data = validate_snapshot(json.loads(payload))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.output.with_suffix('.tmp')
    temporary.write_text(json.dumps(data, ensure_ascii=False, separators=(',', ':')) + '\n')
    temporary.replace(args.output)
    print(f"Aggregate activity snapshot: {data['asOf']}, {len(data['days'])} days")


if __name__ == '__main__':
    main()
