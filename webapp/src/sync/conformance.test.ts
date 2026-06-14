import { test, expect } from "vitest";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { resolve as resolvePath, dirname } from "node:path";
import { resolve as resolveConflict, type Decision } from "./conflictResolver";

interface Scenario {
  name: string;
  localModifiedAt: number | null;
  tombstone: number | null;
  remoteModifiedAt: number;
  remoteDeleted: boolean;
  expect: Decision;
}

// Canonical fixture shared with the Swift engine (sub-project 2).
const fixturePath = resolvePath(
  dirname(fileURLToPath(import.meta.url)),
  "../../../WanderIQKit/Tests/WanderIQKitTests/Fixtures/sync-conformance.json",
);
const scenarios: Scenario[] = JSON.parse(readFileSync(fixturePath, "utf8")).scenarios;

test("the shared conformance fixture is non-empty", () => {
  expect(scenarios.length).toBeGreaterThan(0);
});

test.each(scenarios)("conformance: $name", (s) => {
  expect(resolveConflict(s.localModifiedAt, s.tombstone, s.remoteModifiedAt, s.remoteDeleted))
    .toBe(s.expect);
});
