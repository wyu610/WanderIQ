import { test, expect } from "vitest";
import { newTrip, type Trip } from "./trip";

test("newTrip fills defaults and an id", () => {
  const t: Trip = newTrip({ name: "China" });
  expect(t.name).toBe("China");
  expect(t.id).toMatch(/[0-9a-f-]{36}/);
  expect(t.days).toEqual([]);
  expect(t.items).toEqual([]);
  expect(t.schemaVersion).toBe(1);
});
