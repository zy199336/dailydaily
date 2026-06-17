function pad(value) {
  return String(value).padStart(2, '0');
}

function toDate(value) {
  if (value instanceof Date) {
    return new Date(value.getFullYear(), value.getMonth(), value.getDate());
  }
  const [year, month, day] = String(value).split('-').map(Number);
  return new Date(year, month - 1, day);
}

function formatDate(date) {
  const d = toDate(date);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

function addDays(date, count) {
  const d = toDate(date);
  d.setDate(d.getDate() + count);
  return d;
}

function diffDays(a, b) {
  const left = toDate(a).getTime();
  const right = toDate(b).getTime();
  return Math.round((left - right) / 86400000);
}

function startOfWeek(date) {
  const d = toDate(date);
  d.setDate(d.getDate() - d.getDay());
  return d;
}

function monthGrid(date) {
  const d = toDate(date);
  const first = new Date(d.getFullYear(), d.getMonth(), 1);
  const start = startOfWeek(first);
  return Array.from({ length: 42 }, (_, index) => addDays(start, index));
}

function weekGrid(date) {
  const start = startOfWeek(date);
  return Array.from({ length: 7 }, (_, index) => addDays(start, index));
}

function isBetween(date, start, end) {
  const target = formatDate(date);
  return target >= formatDate(start) && target <= formatDate(end);
}

function titleFor(date) {
  const d = toDate(date);
  return `${d.getFullYear()}年${d.getMonth() + 1}月`;
}

module.exports = {
  addDays,
  diffDays,
  formatDate,
  isBetween,
  monthGrid,
  startOfWeek,
  titleFor,
  toDate,
  weekGrid,
};
