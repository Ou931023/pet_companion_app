"use strict";

const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const assert = require("node:assert/strict");

const root = __dirname;
const indexHtml = fs.readFileSync(path.join(root, "index.html"), "utf8");
const appJs = fs.readFileSync(path.join(root, "app.js"), "utf8");

test("主導覽收斂成工作台、照護、分析、管理四區", () => {
  assert.ok(indexHtml.includes('id="tab-workspace"'));
  assert.ok(indexHtml.includes('id="tab-care-section"'));
  assert.ok(indexHtml.includes('id="tab-insights-section"'));
  assert.ok(indexHtml.includes('id="tab-management-section"'));
  assert.ok(indexHtml.includes('id="secondary-view-tabs"'));
});

test("既有功能 view 保留，切換時只顯示目前工作區的次選單", () => {
  [
    "tab-alerts",
    "tab-tasks",
    "tab-analytics",
    "tab-health",
    "tab-users",
    "tab-products",
    "tab-orders",
    "tab-caregivers",
    "tab-assignments",
  ].forEach((id) => assert.ok(indexHtml.includes(`id="${id}"`)));
  assert.ok(appJs.includes("syncNavigationForView(name)"));
  assert.ok(appJs.includes('return "management"'));
  assert.ok(appJs.includes('elN.management.classList.toggle("hidden", caregiver)'));
});
