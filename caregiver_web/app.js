// 長照照護管理後台前端邏輯。
// 只讀取後端已保存的 Care Alert，不做登入 / 權限 / 標記已處理。
// 全部資料來自後端 API，沒有任何假資料。

(function () {
  "use strict";

  var API_BASE_KEY = "caregiver_api_base";
  var DEFAULT_API_BASE = "http://127.0.0.1:3001/api";

  // 同時支援權威四級（low/medium/high/urgent）與舊代碼（normal/attention）。
  var RISK_LABELS = {
    urgent: "緊急",
    high: "需通知",
    medium: "持續觀察",
    low: "一般",
    attention: "需注意",
    normal: "一般",
  };
  var STATUS_LABELS = {
    new: "新提醒",
    acknowledged: "已查看",
    resolved: "已處理",
  };

  // 目前在詳情 modal 中顯示的提醒（狀態更新時參照）。
  var selectedAlert = null;

  // ---- DOM ----
  var el = {
    apiBase: document.getElementById("api-base"),
    saveApiBase: document.getElementById("save-api-base"),
    filterRisk: document.getElementById("filter-risk"),
    filterStatus: document.getElementById("filter-status"),
    filterLimit: document.getElementById("filter-limit"),
    refresh: document.getElementById("refresh"),
    statusMessage: document.getElementById("status-message"),
    list: document.getElementById("alert-list"),
    statTotal: document.getElementById("stat-total"),
    statUrgent: document.getElementById("stat-urgent"),
    statNew: document.getElementById("stat-new"),
    overlay: document.getElementById("detail-overlay"),
    detailBody: document.getElementById("detail-body"),
    detailClose: document.getElementById("detail-close"),
  };

  // ---- helpers ----
  function getApiBase() {
    var stored = (localStorage.getItem(API_BASE_KEY) || "").trim();
    return stored || DEFAULT_API_BASE;
  }

  function normalizeBase(value) {
    return (value || "").trim().replace(/\/+$/, "");
  }

  function escapeHtml(value) {
    return String(value == null ? "" : value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  function riskLabel(alert) {
    return alert.riskLevelLabel || RISK_LABELS[alert.riskLevel] || alert.riskLevel || "未知";
  }

  function categoryLabel(alert) {
    return alert.categoryLabel || alert.category || "其他";
  }

  function statusLabel(status) {
    return STATUS_LABELS[status] || status || "—";
  }

  function riskClass(riskLevel) {
    switch (riskLevel) {
      // 權威四級
      case "urgent":
        return "risk-urgent";
      case "high":
        return "risk-high";
      case "medium":
        return "risk-medium";
      case "low":
        return "risk-low";
      // 舊代碼（legacy）
      case "attention":
        return "risk-attention";
      case "normal":
        return "risk-normal";
      default:
        return "";
    }
  }

  function formatTime(iso) {
    if (!iso) return "—";
    var d = new Date(iso);
    if (isNaN(d.getTime())) return String(iso);
    var p = function (n) {
      return String(n).padStart(2, "0");
    };
    return (
      d.getFullYear() +
      "/" +
      p(d.getMonth() + 1) +
      "/" +
      p(d.getDate()) +
      " " +
      p(d.getHours()) +
      ":" +
      p(d.getMinutes())
    );
  }

  function setStatus(text, isError) {
    el.statusMessage.textContent = text || "";
    el.statusMessage.className = "status-message" + (isError ? " error" : "");
  }

  function buildQuery() {
    var params = [];
    var risk = el.filterRisk.value;
    var status = el.filterStatus.value;
    var limit = el.filterLimit.value;
    if (risk) params.push("riskLevel=" + encodeURIComponent(risk));
    if (status) params.push("status=" + encodeURIComponent(status));
    if (limit) params.push("limit=" + encodeURIComponent(limit));
    return params.length ? "?" + params.join("&") : "";
  }

  // ---- render ----
  function renderStats(alerts) {
    el.statTotal.textContent = String(alerts.length);
    el.statUrgent.textContent = String(
      alerts.filter(function (a) {
        return a.riskLevel === "urgent";
      }).length
    );
    el.statNew.textContent = String(
      alerts.filter(function (a) {
        return a.status === "new";
      }).length
    );
  }

  function renderList(alerts) {
    el.list.innerHTML = alerts
      .map(function (a) {
        var rClass = riskClass(a.riskLevel);
        return (
          '<article class="alert-card ' +
          rClass +
          '" data-id="' +
          escapeHtml(a.id) +
          '">' +
          '<div class="card-top">' +
          '<div class="badges">' +
          '<span class="badge ' +
          rClass +
          '">' +
          escapeHtml(riskLabel(a)) +
          "</span>" +
          '<span class="badge">' +
          escapeHtml(categoryLabel(a)) +
          "</span>" +
          '<span class="badge status status-' +
          escapeHtml(a.status) +
          '">' +
          escapeHtml(statusLabel(a.status)) +
          "</span>" +
          "</div>" +
          '<span class="card-time">' +
          escapeHtml(formatTime(a.receivedAt || a.createdAt)) +
          "</span>" +
          "</div>" +
          '<p class="card-summary">' +
          escapeHtml(a.triggerSummary || "（無摘要）") +
          "</p>" +
          "</article>"
        );
      })
      .join("");

    Array.prototype.forEach.call(
      el.list.querySelectorAll(".alert-card"),
      function (card) {
        card.addEventListener("click", function () {
          openDetail(card.getAttribute("data-id"));
        });
      }
    );
  }

  // ---- data ----
  function loadAlerts() {
    setStatus("載入中…", false);
    el.list.innerHTML = "";
    var url = getApiBase() + "/care-alerts" + buildQuery();
    fetch(url)
      .then(function (res) {
        if (!res.ok) throw new Error("HTTP " + res.status);
        return res.json();
      })
      .then(function (data) {
        if (!data || data.success !== true || !Array.isArray(data.alerts)) {
          throw new Error("unexpected response");
        }
        renderStats(data.alerts);
        if (data.alerts.length === 0) {
          setStatus("目前沒有照護提醒紀錄", false);
          return;
        }
        setStatus("", false);
        renderList(data.alerts);
      })
      .catch(function () {
        el.statTotal.textContent = "—";
        el.statUrgent.textContent = "—";
        el.statNew.textContent = "—";
        setStatus("無法取得照護提醒，請確認後端是否啟動", true);
      });
  }

  function openDetail(id) {
    if (!id) return;
    el.detailBody.innerHTML = '<p class="status-message">載入中…</p>';
    el.overlay.classList.remove("hidden");
    fetch(getApiBase() + "/care-alerts/" + encodeURIComponent(id))
      .then(function (res) {
        if (!res.ok) throw new Error("HTTP " + res.status);
        return res.json();
      })
      .then(function (data) {
        if (!data || data.success !== true || !data.alert) {
          throw new Error("unexpected response");
        }
        renderDetail(data.alert);
      })
      .catch(function () {
        el.detailBody.innerHTML =
          '<p class="status-message error">無法取得此筆提醒詳情，請稍後再試</p>';
      });
  }

  function detailRow(key, valueHtml) {
    return (
      '<div class="detail-row"><div class="detail-key">' +
      escapeHtml(key) +
      '</div><div class="detail-val">' +
      valueHtml +
      "</div></div>"
    );
  }

  function buildActionSection(a) {
    if (a.status === "resolved") {
      return (
        '<div class="detail-actions"><p class="detail-done">此提醒已處理</p></div>' +
        '<p id="detail-msg" class="detail-msg"></p>'
      );
    }
    var buttons = "";
    if (a.status === "new") {
      buttons +=
        '<button type="button" class="btn act-btn" data-status="acknowledged">標記為已查看</button>';
    }
    buttons +=
      '<button type="button" class="btn btn-success act-btn" data-status="resolved">標記為已處理</button>';
    return (
      '<div class="detail-actions">' +
      buttons +
      "</div>" +
      '<p id="detail-msg" class="detail-msg"></p>'
    );
  }

  function wireActionButtons() {
    Array.prototype.forEach.call(
      el.detailBody.querySelectorAll(".detail-actions .act-btn"),
      function (btn) {
        btn.addEventListener("click", function () {
          if (!selectedAlert) return;
          updateAlertStatus(selectedAlert.id, btn.getAttribute("data-status"));
        });
      }
    );
  }

  function setDetailMsg(text, isError) {
    var m = document.getElementById("detail-msg");
    if (!m) return;
    m.textContent = text || "";
    m.className = "detail-msg" + (isError ? " error" : "");
  }

  function renderDetail(a) {
    selectedAlert = a;
    el.detailBody.innerHTML =
      detailRow(
        "風險等級",
        '<span class="badge ' +
          riskClass(a.riskLevel) +
          '">' +
          escapeHtml(riskLabel(a)) +
          "</span>"
      ) +
      detailRow("類型", escapeHtml(categoryLabel(a))) +
      detailRow("狀態", escapeHtml(statusLabel(a.status))) +
      detailRow("摘要", escapeHtml(a.triggerSummary || "（無摘要）")) +
      detailRow(
        "對話片段",
        '<div class="detail-snippet">' +
          escapeHtml(a.transcriptSnippet || "（無）") +
          "</div>"
      ) +
      detailRow("建立時間", escapeHtml(formatTime(a.createdAt))) +
      detailRow("收到時間", escapeHtml(formatTime(a.receivedAt))) +
      detailRow("來源", escapeHtml(a.source || "—")) +
      detailRow("ID", escapeHtml(a.id || "—")) +
      buildActionSection(a);
    wireActionButtons();
  }

  function updateAlertStatus(id, status) {
    if (!id || !status) return;
    var buttons = el.detailBody.querySelectorAll(".detail-actions .act-btn");
    Array.prototype.forEach.call(buttons, function (b) {
      b.disabled = true;
    });
    setDetailMsg("更新中…", false);

    fetch(getApiBase() + "/care-alerts/" + encodeURIComponent(id) + "/status", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ status: status }),
    })
      .then(function (res) {
        if (!res.ok) throw new Error("HTTP " + res.status);
        return res.json();
      })
      .then(function (data) {
        if (!data || data.success !== true || !data.alert) {
          throw new Error("unexpected response");
        }
        renderDetail(data.alert); // modal 立即更新（按鈕也會依新狀態重繪）
        setDetailMsg(
          status === "resolved" ? "已標記為已處理" : "已標記為已查看",
          false
        );
        loadAlerts(); // 重新 fetch 列表 + 更新 Dashboard 統計
      })
      .catch(function () {
        Array.prototype.forEach.call(buttons, function (b) {
          b.disabled = false;
        });
        setDetailMsg("狀態更新失敗，請確認後端是否啟動", true);
      });
  }

  function closeDetail() {
    el.overlay.classList.add("hidden");
    selectedAlert = null;
    el.detailBody.innerHTML = "";
  }

  // ---- init ----
  function init() {
    el.apiBase.value = getApiBase();

    el.saveApiBase.addEventListener("click", function () {
      var next = normalizeBase(el.apiBase.value) || DEFAULT_API_BASE;
      localStorage.setItem(API_BASE_KEY, next);
      el.apiBase.value = next;
      loadAlerts();
    });

    el.refresh.addEventListener("click", loadAlerts);
    el.filterRisk.addEventListener("change", loadAlerts);
    el.filterStatus.addEventListener("change", loadAlerts);
    el.filterLimit.addEventListener("change", loadAlerts);

    el.detailClose.addEventListener("click", closeDetail);
    el.overlay.addEventListener("click", function (e) {
      if (e.target === el.overlay) closeDetail();
    });
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape") closeDetail();
    });

    loadAlerts();
  }

  init();
})();
