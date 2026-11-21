// Pure clock-in rules shared by the Cloud Functions — no
// firebase imports, so they are unit-testable with plain
// `node --test` (see test/clock_rules_test.js).
//
// - radiusForSite: the fence radius for a site doc (100 m
//   default when the site has no usable stored radius).
// - isShortAutoEntry: Atto's 10-minute rule — an auto entry
//   closed less than 10 minutes after it opened is a drive-by,
//   not work, and is deleted outright (entry + breadcrumbs).

const shortAutoEntryThresholdMs = 10 * 60 * 1000;

/// Fence radius in metres for a site doc. Falls back to 100
/// when the site is missing or its stored radius is not a
/// positive number (an old doc, or a forged one — the app
/// editor clamps 10–5000 m, but the server never trusts it).
function radiusForSite(site) {
  const r =
    site != null && typeof site.radiusMeters === "number"
      ? site.radiusMeters
      : NaN;
  return Number.isFinite(r) && r > 0 ? r : 100;
}

/// A Firestore Timestamp, a Date, or epoch millis → epoch
/// millis, or null when the value cannot be read.
function timestampMs(value) {
  if (value == null) return null;
  if (typeof value === "number") return value;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  return null;
}

/// True when an AUTO entry closed less than 10 minutes after
/// it opened. Manual entries are never short-auto entries,
/// and a clock-out before the clock-in (bad phone clock)
/// does not count either.
function isShortAutoEntry(auto, clockInMs, clockOutMs) {
  if (auto !== true) return false;
  if (typeof clockInMs !== "number" || typeof clockOutMs !== "number") {
    return false;
  }
  const durationMs = clockOutMs - clockInMs;
  return durationMs >= 0 && durationMs < shortAutoEntryThresholdMs;
}

module.exports = {
  radiusForSite,
  timestampMs,
  isShortAutoEntry,
  shortAutoEntryThresholdMs,
};
