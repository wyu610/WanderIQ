import { test, expect } from "vitest";
import { resolve } from "./conflictResolver";

test("remote upsert newer applies", () =>
  expect(resolve(1, null, 2, false)).toBe("applyRemote"));
test("remote upsert older kept", () =>
  expect(resolve(2, null, 1, false)).toBe("keepLocal"));
test("tie keeps local", () =>
  expect(resolve(2, null, 2, false)).toBe("keepLocal"));
test("remote delete newer than local edit applies", () =>
  expect(resolve(1, null, 2, true)).toBe("applyRemote"));
test("local edit newer than remote delete kept", () =>
  expect(resolve(3, null, 2, true)).toBe("keepLocal"));
test("local tombstone ties remote upsert → stays deleted", () =>
  expect(resolve(null, 2, 2, false)).toBe("keepLocal"));
test("remote upsert newer than tombstone resurrects", () =>
  expect(resolve(null, 1, 2, false)).toBe("applyRemote"));
test("unknown entity remote upsert applies", () =>
  expect(resolve(null, null, 1, false)).toBe("applyRemote"));
