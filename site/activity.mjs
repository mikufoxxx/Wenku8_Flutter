const DAY = 86400000;
const platforms = ['android', 'ios', 'harmony'];
export const shanghaiDay = time => new Date(Date.parse(time) + 8 * 3600000).toISOString().slice(0, 10);
const offset = (day, amount) => new Date(Date.parse(`${day}T00:00:00Z`) + amount * DAY).toISOString().slice(0, 10);
export function validateSnapshot(data) {
  if (!data || Object.keys(data).sort().join(',') !== 'asOf,days,firstDay,schema,timezone' || data.schema !== 1 || data.timezone !== 'Asia/Shanghai' ||
      typeof data.asOf !== 'string' || !Number.isFinite(Date.parse(data.asOf)) || !Array.isArray(data.days) || data.days.length > 30) throw new Error('Invalid activity snapshot');
  const validDate = day => typeof day === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(day) && new Date(`${day}T00:00:00Z`).toISOString().slice(0, 10) === day;
  if (data.firstDay !== null && !validDate(data.firstDay)) throw new Error('Invalid start date');
  let previous;
  for (const row of data.days) {
    if (Object.keys(row).sort().join(',') !== 'active,android,capped,day,harmony,ios' || !validDate(row.day) || row.day > shanghaiDay(data.asOf) ||
        typeof row.capped !== 'boolean' || !['active', ...platforms].every(key => Number.isInteger(row[key]) && row[key] >= 0 && row[key] <= 10000) ||
        row.active !== platforms.reduce((sum, key) => sum + row[key], 0) || previous && row.day !== offset(previous, 1)) throw new Error('Invalid daily value');
    previous = row.day;
  }
  if (data.days.length && (!data.firstDay || data.firstDay > data.days[0].day || data.days.at(-1).day !== shanghaiDay(data.asOf))) throw new Error('Incomplete activity snapshot');
  return data;
}
export function seriesFor(data, range) {
  if (![7, 30].includes(range)) throw new Error('Invalid period');
  const first = offset(shanghaiDay(data.asOf), 1 - range);
  return data.days.filter(row => row.day >= first);
}
export function chartGeometry(rows, width = 1000, height = 300) {
  const maximum = Math.max(2, ...rows.map(row => row.active));
  const power = 10 ** Math.floor(Math.log10(maximum));
  const top = (power === 1 ? [2, 4, 6, 8, 10] : [1, 2, 5, 10]).map(n => n * power).find(n => n >= maximum);
  const left = 56, right = width - 12, baseline = height - 34, plotHeight = height - 54;
  const points = rows.map((row, index) => ({ ...row, x: rows.length === 1 ? (left + right) / 2 : left + index * (right - left) / (rows.length - 1), y: baseline - row.active * plotHeight / top }));
  return { top, points, left, right, baseline, plotHeight, height };
}

async function init() {
  const root = document.querySelector('[data-activity]');
  if (!root) return;
  const locale = root.dataset.locale === 'zh' ? 'zh-CN' : 'en';
  const number = value => new Intl.NumberFormat(locale).format(value);
  const shortDay = day => new Intl.DateTimeFormat(locale, { timeZone: 'UTC', month: 'short', day: 'numeric' }).format(new Date(`${day}T00:00:00Z`));
  const status = root.querySelector('[data-status]');
  const svg = root.querySelector('[data-chart]');
  const svgNode = (tag, attrs = {}, text = '') => {
    const node = document.createElementNS('http://www.w3.org/2000/svg', tag);
    for (const [key, value] of Object.entries(attrs)) node.setAttribute(key, String(value));
    node.textContent = text;
    return node;
  };
  try {
    const response = await fetch('activity.json', { cache: 'no-cache', credentials: 'omit' });
    if (!response.ok) throw new Error('Snapshot unavailable');
    const data = validateSnapshot(await response.json());
    const latest = data.days.at(-1);
    const asOfDay = shanghaiDay(data.asOf);
    const nowDay = shanghaiDay(new Date().toISOString());
    if (asOfDay !== nowDay) root.querySelector('[data-total-label]').textContent = root.dataset.latest;
    root.querySelector('[data-total]').textContent = `${latest?.capped ? '≥ ' : ''}${number(latest?.active ?? 0)}`;
    root.querySelector('[data-day]').textContent = shortDay(asOfDay);
    const updated = root.querySelector('[data-updated]');
    updated.dateTime = data.asOf;
    updated.textContent = new Intl.DateTimeFormat(locale, { timeZone: 'Asia/Shanghai', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit', hour12: false }).format(new Date(data.asOf));
    for (const platform of platforms) {
      root.querySelector(`[data-count="${platform}"]`).textContent = number(latest?.[platform] ?? 0);
      const meter = root.querySelector(`[data-meter="${platform}"]`);
      meter.max = Math.max(1, latest?.active ?? 0); meter.value = latest?.[platform] ?? 0;
    }
    let selected = 7;
    function render(range) {
      selected = range;
      for (const button of root.querySelectorAll('[data-range]')) button.setAttribute('aria-pressed', String(Number(button.dataset.range) === range));
      root.querySelector('[data-period-label]').textContent = locale === 'zh-CN' ? `最近 ${range} 天` : `Last ${range} days`;
      const width = Math.max(260, svg.clientWidth);
      const rows = seriesFor(data, range), { top, points, left, right, baseline, plotHeight, height } = chartGeometry(rows, width, 230);
      svg.setAttribute('viewBox', `0 0 ${width} ${height}`);
      svg.replaceChildren();
      for (const value of [0, top / 2, top]) {
        const y = baseline - value * plotHeight / top;
        svg.append(svgNode('line', { x1: left, x2: right, y1: y, y2: y, class: 'grid' }), svgNode('text', { x: 44, y: y + 5, 'text-anchor': 'end', class: 'axis' }, number(value)));
      }
      if (points.length > 1) {
        const line = points.map((p, i) => `${i ? 'L' : 'M'}${p.x},${p.y}`).join(' ');
        svg.append(svgNode('path', { d: `${line} L${points.at(-1).x},${baseline} L${points[0].x},${baseline} Z`, class: 'area' }), svgNode('path', { d: line, class: 'line' }));
      } else if (points.length) svg.append(svgNode('line', { x1: points[0].x, x2: points[0].x, y1: points[0].y, y2: baseline, class: 'stem' }));
      for (const p of points) {
        const label = `${p.day}: ${p.capped ? '≥ ' : ''}${number(p.active)}`;
        const circle = svgNode('circle', { cx: p.x, cy: p.y, r: points.length === 1 ? 7 : 4, class: 'point', tabindex: 0, 'aria-label': label });
        circle.append(svgNode('title', {}, label)); svg.append(circle);
      }
      const indices = [...new Set(points.length < 3 ? points.map((_, i) => i) : [0, Math.floor((points.length - 1) / 2), points.length - 1])];
      for (const i of indices) svg.append(svgNode('text', { x: points[i].x, y: height - 6, 'text-anchor': i === 0 && points.length > 1 ? 'start' : i === points.length - 1 && points.length > 1 ? 'end' : 'middle', class: 'axis' }, shortDay(points[i].day)));
      const notes = [];
      if (Date.now() - Date.parse(data.asOf) > 3 * 3600000 || asOfDay !== nowDay) notes.push(root.dataset.stale);
      if (rows.some(row => row.capped)) notes.push(root.dataset.capped);
      if (rows.length < 2) notes.push(rows.length ? root.dataset.single : root.dataset.empty);
      status.textContent = notes.join(' ');
      const body = root.querySelector('[data-activity-rows]'); body.replaceChildren();
      for (const row of [...rows].reverse()) {
        const tr = document.createElement('tr');
        const dateCell = document.createElement('td'), time = document.createElement('time');
        time.dateTime = row.day; time.setAttribute('aria-label', row.day); time.title = row.day;
        for (const [className, text] of [['date-full', row.day], ['date-short', new Intl.DateTimeFormat(locale, { timeZone: 'UTC', month: '2-digit', day: '2-digit' }).format(new Date(`${row.day}T00:00:00Z`))]]) {
          const span = document.createElement('span'); span.className = className; span.textContent = text; time.append(span);
        }
        dateCell.append(time); tr.append(dateCell);
        for (const value of [`${row.capped ? '≥ ' : ''}${number(row.active)}`, ...platforms.map(key => number(row[key]))]) {
          const cell = document.createElement('td'); cell.textContent = value; tr.append(cell);
        }
        body.append(tr);
      }
    }
    for (const button of root.querySelectorAll('[data-range]')) button.addEventListener('click', () => render(Number(button.dataset.range)));
    render(7);
    if (typeof ResizeObserver !== 'undefined') new ResizeObserver(() => render(selected)).observe(svg.parentElement);
  } catch {
    status.textContent = root.dataset.error;
    for (const button of root.querySelectorAll('[data-range]')) button.disabled = true;
  }
}
if (typeof document !== 'undefined') init();
