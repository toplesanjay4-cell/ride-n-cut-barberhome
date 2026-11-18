const JAKARTA_TIME_ZONE = "Asia/Jakarta";
const jakartaDateFormatter = new Intl.DateTimeFormat("en-CA", {
  timeZone: JAKARTA_TIME_ZONE,
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
});
const jakartaTimeFormatter = new Intl.DateTimeFormat("en-GB", {
  timeZone: JAKARTA_TIME_ZONE,
  hour: "2-digit",
  minute: "2-digit",
  hourCycle: "h23",
});

/** @param {string} dateKey */
function parseDateKey(dateKey) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dateKey);
  if (!match) return null;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  if (year < 1000 || month < 1 || month > 12 || day < 1 || day > 31) return null;
  const timestamp = Date.UTC(year, month - 1, day);
  const date = new Date(timestamp);
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day) return null;
  return { year, month, day, timestamp };
}

/** @param {Date|string|number} [value] */
export function getJakartaDateKey(value = new Date()) {
  const date = value instanceof Date ? value : new Date(String(value));
  if (!Number.isFinite(date.getTime())) throw new RangeError("Tanggal tidak valid.");
  const parts = Object.fromEntries(jakartaDateFormatter.formatToParts(date).map(part => [part.type, part.value]));
  return `${parts.year}-${parts.month}-${parts.day}`;
}

/** @param {Date|string|number} [value] */
export function getJakartaTimeKey(value = new Date()) {
  const date = value instanceof Date ? value : new Date(String(value));
  if (!Number.isFinite(date.getTime())) throw new RangeError("Waktu tidak valid.");
  const parts = Object.fromEntries(jakartaTimeFormatter.formatToParts(date).map(part => [part.type, part.value]));
  return `${parts.hour}:${parts.minute}`;
}

/** @param {string} dateKey @param {number} days */
export function addDateKeyDays(dateKey, days) {
  const parsed = parseDateKey(dateKey);
  if (!parsed || !Number.isInteger(days)) throw new RangeError("Tanggal atau jumlah hari tidak valid.");
  const date = new Date(parsed.timestamp);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

/** @param {string} dateKey */
export function getDateKeyWeekday(dateKey) {
  const parsed = parseDateKey(dateKey);
  return parsed ? new Date(parsed.timestamp).getUTCDay() : null;
}

/** @param {string} dateKey @param {number} months */
export function addDateKeyMonths(dateKey, months) {
  const parsed = parseDateKey(dateKey);
  if (!parsed || !Number.isInteger(months)) throw new RangeError("Tanggal atau jumlah bulan tidak valid.");
  return new Date(Date.UTC(parsed.year, parsed.month - 1 + months, 1)).toISOString().slice(0, 10);
}

/** @param {string} dateKey */
export function getJakartaMonthStart(dateKey) {
  const parsed = parseDateKey(dateKey);
  if (!parsed) throw new RangeError("Tanggal tidak valid.");
  return `${parsed.year}-${String(parsed.month).padStart(2, "0")}-01`;
}

/** @param {string} dateKey */
export function getJakartaYearStart(dateKey) {
  const parsed = parseDateKey(dateKey);
  if (!parsed) throw new RangeError("Tanggal tidak valid.");
  return `${parsed.year}-01-01`;
}

/** @param {string} dateKey @param {string} time */
export function jakartaDateTimeToISOString(dateKey, time) {
  if (!parseDateKey(dateKey) || !/^(?:[01]\d|2[0-3]):[0-5]\d$/.test(time)) return null;
  return new Date(`${dateKey}T${time}:00+07:00`).toISOString();
}

/** @param {string} dateKey @param {Intl.DateTimeFormatOptions} [options] */
export function formatJakartaDateKey(dateKey, options = {}) {
  if (!parseDateKey(dateKey)) return dateKey;
  const date = new Date(`${dateKey}T12:00:00+07:00`);
  return new Intl.DateTimeFormat("id-ID", { timeZone: JAKARTA_TIME_ZONE, ...options }).format(date);
}

/** @param {Date|string|number} value @param {Intl.DateTimeFormatOptions} [options] */
export function formatJakartaDateTime(value, options = {}) {
  const date = value instanceof Date ? value : new Date(String(value));
  if (!Number.isFinite(date.getTime())) return "-";
  return new Intl.DateTimeFormat("id-ID", { timeZone: JAKARTA_TIME_ZONE, ...options }).format(date);
}
