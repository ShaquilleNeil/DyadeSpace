// Pure unit tests for functions/clock_rules.js — no emulator,
// no Firebase: `node --test test/clock_rules_test.js`.
const test = require("node:test");
const assert = require("node:assert/strict");
const {
  radiusForSite,
  timestampMs,
  isShortAutoEntry,
  shortAutoEntryThresholdMs,
} = require("../clock_rules");

test("threshold is 10 minutes", () => {
  assert.equal(shortAutoEntryThresholdMs, 10 * 60 * 1000);
});

test("radiusForSite: stored radius wins", () => {
  assert.equal(radiusForSite({ radiusMeters: 250 }), 250);
  assert.equal(radiusForSite({ radiusMeters: 50 }), 50);
});

test("radiusForSite: missing/invalid radius falls back to 100", () => {
  assert.equal(radiusForSite(null), 100);
  assert.equal(radiusForSite({}), 100);
  assert.equal(radiusForSite({ radiusMeters: null }), 100);
  assert.equal(radiusForSite({ radiusMeters: "100" }), 100);
  assert.equal(radiusForSite({ radiusMeters: 0 }), 100);
  assert.equal(radiusForSite({ radiusMeters: -50 }), 100);
  assert.equal(radiusForSite({ radiusMeters: NaN }), 100);
});

test("timestampMs: Timestamp-like, Date, number, junk", () => {
  assert.equal(timestampMs({ toMillis: () => 12345 }), 12345);
  assert.equal(timestampMs(new Date(1700000000000)), 1700000000000);
  assert.equal(timestampMs(999), 999);
  assert.equal(timestampMs(null), null);
  assert.equal(timestampMs("nope"), null);
});

test("isShortAutoEntry: auto + under 10 minutes", () => {
  assert.equal(isShortAutoEntry(true, 1000, 1000 + 9 * 60 * 1000), true);
  assert.equal(isShortAutoEntry(true, 1000, 1000 + 599999), true);
});

test("isShortAutoEntry: auto + 10 minutes or more is kept", () => {
  assert.equal(isShortAutoEntry(true, 1000, 1000 + 10 * 60 * 1000), false);
  assert.equal(isShortAutoEntry(true, 1000, 1000 + 60 * 60 * 1000), false);
});

test("isShortAutoEntry: manual entries are never deleted", () => {
  assert.equal(isShortAutoEntry(false, 1000, 1000 + 60 * 1000), false);
  assert.equal(isShortAutoEntry(undefined, 1000, 1000 + 60 * 1000), false);
});

test("isShortAutoEntry: bad timestamps do not count", () => {
  assert.equal(isShortAutoEntry(true, null, 1000), false);
  assert.equal(isShortAutoEntry(true, 1000, null), false);
  // Clock-out before clock-in (bad phone clock): not a drive-by.
  assert.equal(isShortAutoEntry(true, 5000, 1000), false);
});
