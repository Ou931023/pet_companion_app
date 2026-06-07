// 長照照護管理後台前端邏輯。
// 只讀取後端已保存的 Care Alert，不做登入 / 權限 / 標記已處理。
// 全部資料來自後端 API，沒有任何假資料。

(function () {
  "use strict";

  var API_BASE_KEY = "caregiver_api_base";
  var DEFAULT_API_BASE = "http://127.0.0.1:3001/api";
  // CR-0029：管理者權杖只存在本機 localStorage，不寫死、不進 Git。
  var ADMIN_TOKEN_KEY = "caregiver_admin_token";

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
    listCount: document.getElementById("list-count"),
    statNew: document.getElementById("stat-new"),
    statHigh: document.getElementById("stat-high"),
    statUrgent: document.getElementById("stat-urgent"),
    statResolved: document.getElementById("stat-resolved"),
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

  // 顯示關懷對象（長者）。優先採用後端帶來的名稱欄位，否則退回來源識別碼。
  function elderName(alert) {
    return (
      alert.elderName ||
      alert.userName ||
      alert.userId ||
      alert.source ||
      "長者"
    );
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
  function countBy(alerts, predicate) {
    return String(alerts.filter(predicate).length);
  }

  function renderStats(alerts) {
    el.statNew.textContent = countBy(alerts, function (a) {
      return a.status === "new";
    });
    el.statHigh.textContent = countBy(alerts, function (a) {
      return a.riskLevel === "high";
    });
    el.statUrgent.textContent = countBy(alerts, function (a) {
      return a.riskLevel === "urgent";
    });
    el.statResolved.textContent = countBy(alerts, function (a) {
      return a.status === "resolved";
    });
  }

  function resetStats() {
    el.statNew.textContent = "—";
    el.statHigh.textContent = "—";
    el.statUrgent.textContent = "—";
    el.statResolved.textContent = "—";
  }

  function setListCount(n) {
    el.listCount.textContent = n > 0 ? "共 " + n + " 筆" : "";
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
          '<p class="card-elder">👵 ' +
          escapeHtml(elderName(a)) +
          "</p>" +
          '<p class="card-summary">' +
          escapeHtml(a.triggerSummary || "（無摘要）") +
          "</p>" +
          '<div class="card-foot"><span class="card-more">查看詳情 →</span></div>' +
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
        setListCount(data.alerts.length);
        if (data.alerts.length === 0) {
          setStatus("目前一切平安，沒有需要關心的提醒 🌿", false);
          return;
        }
        setStatus("", false);
        renderList(data.alerts);
      })
      .catch(function () {
        resetStats();
        setListCount(0);
        setStatus("暫時連不上後端，請確認服務是否已啟動後再重新整理", true);
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
    var banner =
      '<div class="detail-banner ' +
      riskClass(a.riskLevel) +
      '">' +
      '<div class="detail-banner-elder">👵 ' +
      escapeHtml(elderName(a)) +
      "</div>" +
      '<div class="detail-banner-risk">' +
      '<span class="risk-dot"></span>' +
      "風險等級：" +
      escapeHtml(riskLabel(a)) +
      "</div>" +
      '<span class="badge status status-' +
      escapeHtml(a.status) +
      '">' +
      escapeHtml(statusLabel(a.status)) +
      "</span>" +
      "</div>";

    var summaryBlock =
      '<div class="detail-summary">' +
      '<div class="detail-key">摘要</div>' +
      '<p class="detail-summary-text">' +
      escapeHtml(a.triggerSummary || "（無摘要）") +
      "</p>" +
      "</div>";

    el.detailBody.innerHTML =
      banner +
      summaryBlock +
      detailRow("長者", escapeHtml(elderName(a))) +
      detailRow("類型", escapeHtml(categoryLabel(a))) +
      detailRow(
        "對話片段",
        '<div class="detail-snippet">' +
          escapeHtml(a.transcriptSnippet || "（無）") +
          "</div>"
      ) +
      detailRow("建立時間", escapeHtml(formatTime(a.createdAt))) +
      detailRow("收到時間", escapeHtml(formatTime(a.receivedAt))) +
      detailRow("來源", escapeHtml(a.source || "—")) +
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

  // ========== 健康分析 Dashboard（CR-0007 Batch 4）==========
  // 使用後端 6 條 /api/admin/* 端點；只對應實際 response 欄位，不假造欄位。
  var elH = {
    tabAlerts: document.getElementById("tab-alerts"),
    tabHealth: document.getElementById("tab-health"),
    viewAlerts: document.getElementById("view-alerts"),
    viewHealth: document.getElementById("view-health"),
    healthRefresh: document.getElementById("health-refresh"),
    ovTotal: document.getElementById("ov-total"),
    ovActive: document.getElementById("ov-active"),
    ovAlerts: document.getElementById("ov-alerts"),
    ovHighrisk: document.getElementById("ov-highrisk"),
    ovEmotion: document.getElementById("ov-emotion"),
    ovCognitive: document.getElementById("ov-cognitive"),
    elderList: document.getElementById("elder-list"),
    elderListStatus: document.getElementById("elder-list-status"),
    healthStatus: document.getElementById("health-status"),
    elderAnalysis: document.getElementById("elder-analysis"),
    analysisProfile: document.getElementById("analysis-profile"),
    physioBody: document.getElementById("physio-body"),
    psychBody: document.getElementById("psych-body"),
    emotionBody: document.getElementById("emotion-body"),
    gameBody: document.getElementById("game-body"),
    healthAlertsBody: document.getElementById("health-alerts-body"),
  };
  var healthLoaded = false;
  var activeElderId = null;

  // CR-0025 日常任務追蹤 view 的元素參照。
  var elT = {
    tabTasks: document.getElementById("tab-tasks"),
    viewTasks: document.getElementById("view-tasks"),
    tasksRefresh: document.getElementById("tasks-refresh"),
    tasksFilter: document.getElementById("tasks-filter"),
    tasksStatus: document.getElementById("tasks-status"),
    taskList: document.getElementById("task-list"),
    statTotal: document.getElementById("task-stat-total"),
    statCompleted: document.getElementById("task-stat-completed"),
    statPending: document.getElementById("task-stat-pending"),
    statReview: document.getElementById("task-stat-review"),
    statMissed: document.getElementById("task-stat-missed"),
  };
  var tasksLoaded = false;

  // CR-0029 使用者管理 view 元素參照。
  var elU = {
    tabUsers: document.getElementById("tab-users"),
    viewUsers: document.getElementById("view-users"),
    adminToken: document.getElementById("admin-token"),
    saveAdminToken: document.getElementById("save-admin-token"),
    usersRefresh: document.getElementById("users-refresh"),
    usersStatus: document.getElementById("users-status"),
    usersCount: document.getElementById("users-count"),
    usersTableWrap: document.getElementById("users-table-wrap"),
  };
  var usersLoaded = false;

  // CR-0032 長照商品商城：商品管理 / 訂單管理 element 快取。
  var elP = {
    tabProducts: document.getElementById("tab-products"),
    viewProducts: document.getElementById("view-products"),
    adminToken: document.getElementById("products-admin-token"),
    saveToken: document.getElementById("products-save-token"),
    filter: document.getElementById("products-filter"),
    refresh: document.getElementById("products-refresh"),
    add: document.getElementById("product-add"),
    status: document.getElementById("products-status"),
    count: document.getElementById("products-count"),
    tableWrap: document.getElementById("products-table-wrap"),
    overlay: document.getElementById("product-overlay"),
    formTitle: document.getElementById("product-form-title"),
    form: document.getElementById("product-form"),
    formClose: document.getElementById("product-form-close"),
    formCancel: document.getElementById("product-form-cancel"),
    formStatus: document.getElementById("product-form-status"),
    fId: document.getElementById("pf-id"),
    fName: document.getElementById("pf-name"),
    fCategory: document.getElementById("pf-category"),
    fDescription: document.getElementById("pf-description"),
    fCenterName: document.getElementById("pf-center-name"),
    fCenterId: document.getElementById("pf-center-id"),
    fPrice: document.getElementById("pf-price"),
    fStock: document.getElementById("pf-stock"),
    fCommission: document.getElementById("pf-commission"),
    fStatus: document.getElementById("pf-status"),
    fImage: document.getElementById("pf-image"),
  };
  var productsLoaded = false;

  var elO = {
    tabOrders: document.getElementById("tab-orders"),
    viewOrders: document.getElementById("view-orders"),
    adminToken: document.getElementById("orders-admin-token"),
    saveToken: document.getElementById("orders-save-token"),
    filter: document.getElementById("orders-filter"),
    refresh: document.getElementById("orders-refresh"),
    status: document.getElementById("orders-status"),
    count: document.getElementById("orders-count"),
    list: document.getElementById("orders-list"),
    overlay: document.getElementById("order-overlay"),
    detailBody: document.getElementById("order-detail-body"),
    detailClose: document.getElementById("order-detail-close"),
  };
  var ordersLoaded = false;

  var ORDER_STATUS_LABELS = {
    pending: "待處理",
    confirmed: "已確認",
    shipping: "配送中",
    completed: "已完成",
    cancelled: "已取消",
  };
  var ORDER_STATUS_FLOW = [
    "pending",
    "confirmed",
    "shipping",
    "completed",
    "cancelled",
  ];

  function adminUrl(path) {
    return getApiBase() + "/admin" + path;
  }
  // 長者端公開商城路由（非 /admin）。
  function marketplaceUrl(path) {
    return getApiBase() + "/marketplace" + path;
  }
  // NT$ 千分位金額。
  function formatMoney(n) {
    var num = Number(n);
    if (!isFinite(num)) num = 0;
    return "NT$ " + Math.round(num).toLocaleString("en-US");
  }
  function pct(v) {
    if (typeof v !== "number" || isNaN(v)) return "—";
    return Math.round(v * 100) + "%";
  }
  function avgOf(arr, key) {
    if (!arr || !arr.length) return 0;
    var sum = 0;
    for (var i = 0; i < arr.length; i += 1) sum += Number(arr[i][key]) || 0;
    return sum / arr.length;
  }
  function riskBadge(riskLevel) {
    if (!riskLevel) return "";
    var label = RISK_LABELS[riskLevel] || riskLevel;
    return (
      '<span class="risk-badge ' +
      riskClass(riskLevel) +
      '">' +
      escapeHtml(label) +
      "</span>"
    );
  }
  function barRow(label, ratio) {
    var w = Math.max(0, Math.min(100, Math.round((Number(ratio) || 0) * 100)));
    return (
      '<div class="bar-row"><span class="bar-label">' +
      escapeHtml(label) +
      '</span><span class="bar-track"><span class="bar-fill" style="width:' +
      w +
      '%"></span></span><span class="bar-val">' +
      w +
      "%</span></div>"
    );
  }
  function metricCard(label, value, sub) {
    return (
      '<div class="metric-card"><div class="metric-label">' +
      escapeHtml(label) +
      '</div><div class="metric-value">' +
      escapeHtml(value) +
      "</div>" +
      (sub ? '<div class="metric-sub">' + escapeHtml(sub) + "</div>" : "") +
      "</div>"
    );
  }

  function showView(name) {
    var views = {
      alerts: { view: elH.viewAlerts, tab: elH.tabAlerts },
      health: { view: elH.viewHealth, tab: elH.tabHealth },
      tasks: { view: elT.viewTasks, tab: elT.tabTasks },
      users: { view: elU.viewUsers, tab: elU.tabUsers },
      products: { view: elP.viewProducts, tab: elP.tabProducts },
      orders: { view: elO.viewOrders, tab: elO.tabOrders },
    };
    Object.keys(views).forEach(function (key) {
      var active = key === name;
      var entry = views[key];
      if (entry.view) {
        entry.view.classList.toggle("hidden", !active);
        entry.view.setAttribute("aria-hidden", active ? "false" : "true");
      }
      if (entry.tab) entry.tab.classList.toggle("is-active", active);
    });
    if (name === "health" && !healthLoaded) {
      healthLoaded = true;
      loadHealthOverview();
      loadElderList();
    }
    if (name === "tasks" && !tasksLoaded) {
      tasksLoaded = true;
      loadDailyTasks();
    }
    if (name === "users" && !usersLoaded) {
      usersLoaded = true;
      loadUsers();
    }
    if (name === "products" && !productsLoaded) {
      productsLoaded = true;
      loadProducts();
    }
    if (name === "orders" && !ordersLoaded) {
      ordersLoaded = true;
      loadOrders();
    }
  }

  // ---- CR-0029 使用者管理 ----

  function getAdminToken() {
    return (localStorage.getItem(ADMIN_TOKEN_KEY) || "").trim();
  }

  // 帶 Admin token 的 fetch headers（無 token 時不帶，由後端回 401）。
  function adminAuthHeaders() {
    var token = getAdminToken();
    return token ? { Authorization: "Bearer " + token } : {};
  }

  function authProviderLabel(provider) {
    switch ((provider || "").toLowerCase()) {
      case "google":
        return "Google";
      case "apple":
        return "Apple";
      case "email":
        return "Email";
      default:
        return provider || "—";
    }
  }

  function emailVerifiedLabel(verified) {
    return verified ? "已驗證" : "未驗證";
  }

  function lastLoginLabel(value) {
    if (!value) return "尚未登入或無紀錄";
    return formatTime(value);
  }

  // 後端已遮蔽 email；前端直接顯示 emailMasked，缺值時不顯示原始資料。
  function renderUsers(users) {
    if (!users.length) {
      elU.usersTableWrap.innerHTML = "";
      setUsersStatus("目前尚無使用者帳戶資料", "");
      elU.usersCount.textContent = "";
      return;
    }
    setUsersStatus("", "");
    elU.usersCount.textContent = "共 " + users.length + " 筆";
    var rows = users
      .map(function (u) {
        return (
          "<tr>" +
          '<td class="user-id">' + escapeHtml(u.id) + "</td>" +
          "<td>" + escapeHtml(u.displayName || "—") + "</td>" +
          "<td>" + escapeHtml(u.emailMasked || "—") + "</td>" +
          "<td>" + escapeHtml(authProviderLabel(u.authProvider)) + "</td>" +
          '<td>' +
          '<span class="verify-badge ' +
          (u.emailVerified ? "is-verified" : "is-unverified") +
          '">' +
          escapeHtml(emailVerifiedLabel(u.emailVerified)) +
          "</span></td>" +
          "<td>" + escapeHtml(formatTime(u.createdAt)) + "</td>" +
          "<td>" + escapeHtml(lastLoginLabel(u.lastLoginAt)) + "</td>" +
          "</tr>"
        );
      })
      .join("");
    elU.usersTableWrap.innerHTML =
      '<table class="users-table"><thead><tr>' +
      "<th>使用者 ID</th><th>姓名</th><th>Email</th><th>登入方式</th>" +
      "<th>驗證狀態</th><th>註冊時間</th><th>最近登入</th>" +
      "</tr></thead><tbody>" +
      rows +
      "</tbody></table>";
  }

  function setUsersStatus(message, kind) {
    elU.usersStatus.textContent = message || "";
    elU.usersStatus.classList.toggle("error", kind === "error");
  }

  function loadUsers() {
    elU.usersTableWrap.innerHTML = "";
    elU.usersCount.textContent = "";
    if (!getAdminToken()) {
      setUsersStatus("請先在下方輸入管理者權杖（Admin Token），再重新整理。", "error");
      return;
    }
    setUsersStatus("使用者資料載入中...", "");
    fetch(adminUrl("/users"), { headers: adminAuthHeaders() })
      .then(function (res) {
        if (res.status === 401 || res.status === 403) {
          throw new Error("unauthorized");
        }
        if (!res.ok) throw new Error("HTTP " + res.status);
        return res.json();
      })
      .then(function (body) {
        if (!body || body.ok !== true || !Array.isArray(body.users)) {
          throw new Error("bad_payload");
        }
        renderUsers(body.users);
      })
      .catch(function (err) {
        if (err && err.message === "unauthorized") {
          setUsersStatus(
            "管理者權杖無效或未授權，請確認 Admin Token 是否正確。",
            "error"
          );
        } else {
          setUsersStatus(
            "使用者資料載入失敗，請確認後端與資料庫是否已啟動。",
            "error"
          );
        }
      });
  }

  // ---- CR-0025 日常任務追蹤 ----

  function dailyTaskTypeLabel(type) {
    if (type === "hydration") return "喝水";
    if (type === "exercise") return "運動";
    return "吃藥";
  }

  function dailyTaskStatusLabel(status) {
    switch (status) {
      case "completed":
        return "已完成";
      case "submitted":
        return "已送出";
      case "needs_review":
        return "等待查看";
      case "rejected":
        return "未通過";
      case "missed":
        return "已逾時";
      default:
        return "待完成";
    }
  }

  // AI 影像驗證狀態 → 中文。注意：只描述照片是否符合，不宣稱藥物 / 劑量正確。
  function dailyTaskVerificationLabel(status) {
    switch (status) {
      case "passed":
        return "照片相符";
      case "failed":
        return "照片不符";
      default:
        return "需人工確認";
    }
  }

  function summarizeDailyTasks(tasks) {
    var s = { total: tasks.length, completed: 0, pending: 0, review: 0, missed: 0 };
    tasks.forEach(function (t) {
      if (t.status === "completed") s.completed += 1;
      else if (t.status === "needs_review") s.review += 1;
      else if (t.status === "missed") s.missed += 1;
      else s.pending += 1; // pending / submitted / rejected 都算未完成
    });
    return s;
  }

  function dailyTaskProofUrl(submissionId) {
    return (
      getApiBase() +
      "/daily-care-tasks/proof/" +
      encodeURIComponent(submissionId)
    );
  }

  function renderDailyTaskRow(task) {
    var sub = task.latestSubmission;
    var v = sub && sub.verification ? sub.verification : null;
    var aiStatus = v ? dailyTaskVerificationLabel(v.verificationStatus) : "—";
    var aiConfidence =
      v && typeof v.confidence === "number"
        ? Math.round(Math.max(0, Math.min(1, v.confidence)) * 100) + "%"
        : "—";
    var aiReason = v && v.reason ? escapeHtml(v.reason) : "—";
    var completedAt = task.status === "completed" && sub ? formatTime(sub.submittedAt) : "—";
    var proof =
      sub && sub.id
        ? '<a class="task-proof-link" href="' +
          escapeHtml(dailyTaskProofUrl(sub.id)) +
          '" target="_blank" rel="noopener">查看照片</a>'
        : "—";

    return (
      '<div class="task-row" data-status="' +
      escapeHtml(task.status || "pending") +
      '">' +
      '<div class="task-row-main">' +
      '<span class="task-type">' +
      escapeHtml(dailyTaskTypeLabel(task.type)) +
      "</span>" +
      '<span class="task-title">' +
      escapeHtml(task.title || "") +
      "</span>" +
      '<span class="task-elder">長者：' +
      escapeHtml(task.elderId || "—") +
      "</span>" +
      "</div>" +
      '<div class="task-row-meta">' +
      '<span class="task-badge">' +
      escapeHtml(dailyTaskStatusLabel(task.status)) +
      "</span>" +
      "<span>完成時間：" +
      escapeHtml(completedAt) +
      "</span>" +
      "<span>AI 判斷：" +
      escapeHtml(aiStatus) +
      "</span>" +
      "<span>信心：" +
      escapeHtml(aiConfidence) +
      "</span>" +
      "<span>原因：" +
      aiReason +
      "</span>" +
      "<span>照片：" +
      proof +
      "</span>" +
      "</div>" +
      "</div>"
    );
  }

  function renderDailyTasks(tasks) {
    var s = summarizeDailyTasks(tasks);
    elT.statTotal.textContent = s.total;
    elT.statCompleted.textContent = s.completed;
    elT.statPending.textContent = s.pending;
    elT.statReview.textContent = s.review;
    elT.statMissed.textContent = s.missed;

    if (!tasks.length) {
      elT.taskList.innerHTML =
        '<p class="empty">目前沒有符合條件的任務。</p>';
      return;
    }
    elT.taskList.innerHTML = tasks.map(renderDailyTaskRow).join("");
  }

  // GET /api/admin/daily-care-tasks → 任務 + 最新 submission（含 AI 結果）。
  // 後端連不到時 mock-safe：顯示白話訊息、清空統計，不 crash、不假裝有資料。
  function loadDailyTasks() {
    var filter = elT.tasksFilter ? elT.tasksFilter.value : "";
    var url = adminUrl("/daily-care-tasks");
    if (filter) url += "?status=" + encodeURIComponent(filter);
    if (elT.tasksStatus) elT.tasksStatus.textContent = "載入中…";

    fetch(url)
      .then(function (r) {
        if (!r.ok) throw new Error("HTTP " + r.status);
        return r.json();
      })
      .then(function (data) {
        var tasks = data && Array.isArray(data.tasks) ? data.tasks : [];
        renderDailyTasks(tasks);
        if (elT.tasksStatus) elT.tasksStatus.textContent = "";
      })
      .catch(function () {
        ["statTotal", "statCompleted", "statPending", "statReview", "statMissed"].forEach(
          function (k) {
            if (elT[k]) elT[k].textContent = "—";
          }
        );
        if (elT.taskList) elT.taskList.innerHTML = "";
        if (elT.tasksStatus) {
          elT.tasksStatus.textContent = "目前連不到後端，待會再重新整理看看。";
        }
      });
  }

  // GET /api/admin/overview → 六指標
  function loadHealthOverview() {
    fetch(adminUrl("/overview"))
      .then(function (r) {
        if (!r.ok) throw new Error("HTTP " + r.status);
        return r.json();
      })
      .then(function (o) {
        elH.ovTotal.textContent = o.totalElders;
        elH.ovActive.textContent = o.activeToday;
        elH.ovAlerts.textContent = o.careAlertsToday;
        elH.ovHighrisk.textContent = o.highRiskElders;
        elH.ovEmotion.textContent = o.emotionAbnormalElders;
        elH.ovCognitive.textContent = o.cognitiveDeclineElders;
      })
      .catch(function () {
        ["ovTotal", "ovActive", "ovAlerts", "ovHighrisk", "ovEmotion", "ovCognitive"].forEach(
          function (k) {
            elH[k].textContent = "—";
          }
        );
      });
  }

  // GET /api/admin/elders → 長者列表
  function loadElderList() {
    elH.elderListStatus.textContent = "載入中…";
    fetch(adminUrl("/elders"))
      .then(function (r) {
        if (!r.ok) throw new Error("HTTP " + r.status);
        return r.json();
      })
      .then(function (rows) {
        if (!Array.isArray(rows) || rows.length === 0) {
          elH.elderListStatus.textContent = "目前沒有長者資料。";
          elH.elderList.innerHTML = "";
          return;
        }
        elH.elderListStatus.textContent = "";
        renderElderList(rows);
      })
      .catch(function () {
        elH.elderListStatus.textContent =
          "暫時連不上後端，請確認服務已啟動後再重新整理。";
        elH.elderList.innerHTML = "";
      });
  }

  function renderElderList(rows) {
    elH.elderList.innerHTML = rows
      .map(function (r) {
        var flags = "";
        if (r.emotionAbnormal)
          flags += '<span class="flag flag-emotion">情緒異常</span>';
        if (r.cognitiveDecline)
          flags += '<span class="flag flag-cognitive">認知退化</span>';
        return (
          '<li class="elder-item' +
          (r.elderId === activeElderId ? " is-active" : "") +
          '" data-elder-id="' +
          escapeHtml(r.elderId) +
          '" tabindex="0" role="button">' +
          '<div class="elder-item-main"><span class="elder-item-name">' +
          escapeHtml(r.displayName || r.elderId) +
          "</span>" +
          riskBadge(r.latestRiskLevel) +
          '</div><div class="elder-item-sub">最近互動：' +
          escapeHtml(formatTime(r.lastActiveAt)) +
          "</div>" +
          (flags ? '<div class="elder-item-flags">' + flags + "</div>" : "") +
          "</li>"
        );
      })
      .join("");
    Array.prototype.forEach.call(
      elH.elderList.querySelectorAll(".elder-item"),
      function (li) {
        var handler = function () {
          selectElder(li.getAttribute("data-elder-id"));
        };
        li.addEventListener("click", handler);
        li.addEventListener("keydown", function (e) {
          if (e.key === "Enter" || e.key === " ") {
            e.preventDefault();
            handler();
          }
        });
      }
    );
  }

  function selectElder(elderId) {
    activeElderId = elderId;
    Array.prototype.forEach.call(
      elH.elderList.querySelectorAll(".elder-item"),
      function (li) {
        li.classList.toggle(
          "is-active",
          li.getAttribute("data-elder-id") === elderId
        );
      }
    );
    loadElderAnalysis(elderId);
  }

  // GET /api/admin/elders/:elderId → 個人完整分析
  function loadElderAnalysis(elderId) {
    elH.elderAnalysis.classList.add("hidden");
    elH.healthStatus.textContent = "載入中…";
    fetch(adminUrl("/elders/" + encodeURIComponent(elderId)))
      .then(function (r) {
        if (!r.ok) throw new Error("HTTP " + r.status);
        return r.json();
      })
      .then(function (a) {
        elH.healthStatus.textContent = "";
        renderProfile(a.profile || {});
        renderPhysio(a.physio || {});
        renderPsych(a.psych || {});
        renderEmotion(a.emotionHistory || [], a.emotionDataSource);
        renderGame(a.gameMetrics || {});
        renderHealthAlerts(a.careAlerts || []);
        elH.elderAnalysis.classList.remove("hidden");
      })
      .catch(function () {
        elH.healthStatus.textContent =
          "暫時讀不到這位長者的健康分析，請稍後再試。";
      });
  }

  // CR-0030：資料真實性標籤。reference=示範參考、measured=真實紀錄、其餘不顯示。
  function dataSourceBadge(dataSource) {
    if (dataSource === "reference") {
      return '<span class="data-tag data-reference">示範參考資料</span>';
    }
    if (dataSource === "measured") {
      return '<span class="data-tag data-measured">真實紀錄</span>';
    }
    return "";
  }

  // 資料不足空狀態（不捏造資料）。
  function insufficientBlock(hint) {
    return (
      '<p class="muted data-insufficient">資料不足，待累積更多真實紀錄後再顯示' +
      (hint ? "（" + escapeHtml(hint) + "）" : "") +
      "。</p>"
    );
  }

  function isInsufficient(dataSource, series) {
    return dataSource === "insufficient" || !series || series.length === 0;
  }

  function renderProfile(p) {
    var bits = [];
    if (p.birthYear) bits.push("出生年 " + escapeHtml(String(p.birthYear)));
    if (p.gender) bits.push(escapeHtml(p.gender));
    if (p.bindingStatus) bits.push("綁定狀態：" + escapeHtml(p.bindingStatus));
    elH.analysisProfile.innerHTML =
      '<div class="profile-head"><span class="profile-name">' +
      escapeHtml(p.displayName || p.elderId || "長者") +
      "</span></div>" +
      (bits.length ? '<div class="profile-meta">' + bits.join("　｜　") + "</div>" : "");
  }

  // 生理健康分析：睡眠 / 活動量 / 提醒‧用藥‧喝水‧運動完成度 / 趨勢摘要
  function renderPhysio(physio) {
    var s = physio.summary || {};
    var series = physio.series || [];
    if (isInsufficient(physio.dataSource, series)) {
      elH.physioBody.innerHTML = insufficientBlock("尚無生理 / 生活紀錄來源");
      return;
    }
    var latest = series.length ? series[series.length - 1] : {};
    var html =
      dataSourceBadge(physio.dataSource) +
      '<div class="metric-grid">' +
      metricCard(
        "平均睡眠",
        s.avgSleepHours != null ? s.avgSleepHours + " 小時" : "—",
        latest.sleepQuality ? "最近：" + latest.sleepQuality : ""
      ) +
      metricCard(
        "每日互動",
        s.avgDailyInteractionMinutes != null
          ? s.avgDailyInteractionMinutes + " 分鐘"
          : "—",
        "近 " + series.length + " 天平均"
      ) +
      "</div>";
    html +=
      '<div class="bars">' +
      barRow("提醒完成度", s.avgReminderCompletionRate) +
      barRow("用藥完成度", s.avgMedicationCompletionRate) +
      barRow("喝水完成度", s.avgWaterCompletionRate) +
      barRow("運動完成度", s.avgExerciseCompletionRate) +
      "</div>";
    html +=
      '<p class="analysis-summary">近 ' +
      series.length +
      " 天平均睡眠約 " +
      (s.avgSleepHours != null ? s.avgSleepHours : "—") +
      " 小時、每日互動約 " +
      (s.avgDailyInteractionMinutes != null
        ? s.avgDailyInteractionMinutes
        : "—") +
      " 分鐘，提醒完成率 " +
      pct(s.avgReminderCompletionRate) +
      "。</p>";
    elH.physioBody.innerHTML = html;
  }

  // 心理健康分析：情緒穩定度 / 風險訊號 / 摘要 / 建議照護行動
  function renderPsych(psych) {
    if (psych.dataSource === "insufficient" || !psych.summary) {
      elH.psychBody.innerHTML = insufficientBlock("尚無足夠情緒紀錄可分析");
      return;
    }
    var stable = !psych.abnormal;
    var html =
      dataSourceBadge(psych.dataSource) +
      '<div class="psych-head"><span class="psych-state ' +
      (stable ? "state-ok" : "state-warn") +
      '">情緒穩定度：' +
      (stable ? "穩定" : "需要關注") +
      "</span>" +
      (psych.dominantEmotion
        ? '<span class="psych-dom">主要情緒：' +
          escapeHtml(psych.dominantEmotion) +
          "</span>"
        : "") +
      "</div>";
    if (psych.abnormal)
      html +=
        '<div class="risk-signal">⚠️ 近期較常出現孤單 / 低落 / 焦慮等訊號，建議多加關心。</div>';
    if (psych.summary)
      html += '<p class="analysis-summary">' + escapeHtml(psych.summary) + "</p>";
    html +=
      '<div class="advice"><strong>建議照護行動：</strong>' +
      (psych.abnormal
        ? "安排家人或志工增加陪伴與通話，必要時聯繫長照人員。"
        : "維持目前的陪伴與問候節奏即可。") +
      "</div>";
    elH.psychBody.innerHTML = html;
  }

  // 情緒分析歷史：原生時間軸（不引入 chart 套件）
  function renderEmotion(history, dataSource) {
    if (isInsufficient(dataSource, history)) {
      elH.emotionBody.innerHTML = insufficientBlock("尚無情緒歷史紀錄");
      return;
    }
    var recent = history.slice(-8).reverse();
    elH.emotionBody.innerHTML =
      dataSourceBadge(dataSource) +
      '<ul class="emotion-timeline">' +
      recent
        .map(function (e) {
          var w = Math.round((Number(e.score) || 0) * 100);
          return (
            '<li class="emotion-row"><span class="emotion-date">' +
            escapeHtml(e.date) +
            '</span><span class="emotion-tag">' +
            escapeHtml(e.emotion) +
            '</span><span class="bar-track small"><span class="bar-fill" style="width:' +
            w +
            '%"></span></span><span class="emotion-summary">' +
            escapeHtml(e.summary || "") +
            "</span></li>"
          );
        })
        .join("") +
      "</ul>";
  }

  // 遊戲認知退化指標：認知分數 / 正確率 / 平均時長 / 趨勢 / 是否需關注
  function renderGame(game) {
    var series = game.series || [];
    if (isInsufficient(game.dataSource, series)) {
      elH.gameBody.innerHTML = insufficientBlock("尚無小遊戲紀錄");
      return;
    }
    var latest = series.length ? series[series.length - 1] : {};
    var declining = game.trend === "declining" || game.abnormal;
    var html =
      dataSourceBadge(game.dataSource) +
      '<div class="metric-grid">' +
      metricCard(
        "認知分數",
        latest.cognitiveScore != null ? String(latest.cognitiveScore) : "—",
        "最新一次"
      ) +
      metricCard("平均正確率", pct(avgOf(series, "completionRate")), "近 " + series.length + " 次") +
      metricCard(
        "平均遊戲時長",
        series.length ? Math.round(avgOf(series, "durationSeconds")) + " 秒" : "—",
        "反應參考"
      ) +
      "</div>";
    html +=
      '<div class="spark">' +
      series
        .map(function (g) {
          var w = Math.max(2, Math.min(100, Math.round(Number(g.cognitiveScore) || 0)));
          return (
            '<span class="spark-bar' +
            (g.regressionFlag ? " is-low" : "") +
            '" style="height:' +
            w +
            '%" title="' +
            escapeHtml(g.date) +
            "：" +
            escapeHtml(String(g.cognitiveScore)) +
            '"></span>'
          );
        })
        .join("") +
      "</div>";
    html +=
      '<div class="game-trend ' +
      (declining ? "state-warn" : "state-ok") +
      '">最近趨勢：' +
      (declining ? "認知表現緩降，需要關注" : "表現穩定") +
      "</div>";
    elH.gameBody.innerHTML = html;
  }

  // Care Alert 整合：近期提醒，high / urgent 清楚可見（重用既有 risk 樣式）
  function renderHealthAlerts(alerts) {
    if (!alerts.length) {
      elH.healthAlertsBody.innerHTML =
        '<p class="muted">近期沒有照護提醒，一切平安 🌿</p>';
      return;
    }
    var top = alerts.slice(0, 5);
    elH.healthAlertsBody.innerHTML = top
      .map(function (a) {
        return (
          '<div class="health-alert ' +
          riskClass(a.riskLevel) +
          '"><div class="ha-head">' +
          riskBadge(a.riskLevel) +
          '<span class="ha-cat">' +
          escapeHtml(categoryLabel(a)) +
          '</span><span class="ha-time">' +
          escapeHtml(formatTime(a.receivedAt || a.createdAt)) +
          '</span></div><div class="ha-summary">' +
          escapeHtml(a.triggerSummary || "") +
          "</div></div>"
        );
      })
      .join("");
  }

  // ---- 使用說明導覽（Guided Tour） ----
  // 一步步用高亮 + 說明卡介紹六個分頁與主要操作；切換分頁沿用 showView()，
  // 不另外動資料流。第一次造訪自動播放一次，之後可從右上「使用說明」重看。
  var TOUR_DONE_KEY = "caregiver_tour_done";

  // 每一步：view = 要切到哪個分頁；target = 高亮的元素選擇器（null 置中）。
  var TOUR_STEPS = [
    {
      view: "alerts",
      target: null,
      title: "歡迎使用長者關懷管理中心",
      body: "這裡讓家屬或長照人員，查看 AI 陪伴寵物在日常聊天中留意到的長者身心狀況。接下來用幾步帶您看過六個主要分頁。",
    },
    {
      view: "alerts",
      target: ".view-tabs",
      title: "六個分頁",
      body: "上方可切換「照護提醒、健康分析、日常任務、使用者管理、商品管理、訂單管理」。平常最常看的是第一頁的照護提醒。",
    },
    {
      view: "alerts",
      target: "#stats",
      title: "關懷概況",
      body: "這四張卡是一眼可看的重點：新提醒、需通知、緊急、已處理的數量。數字會隨提醒進來即時更新。",
    },
    {
      view: "alerts",
      target: ".filters",
      title: "篩選提醒",
      body: "可依風險等級、處理狀態、顯示筆數篩選，再按「重新整理」。想先看緊急或待處理的提醒時很方便。",
    },
    {
      view: "alerts",
      target: ".list-section",
      title: "提醒列表與處理",
      body: "點任一張提醒卡可看詳情，裡面能把它標記為「已查看」或「已處理」。處理完的提醒會記錄起來，不會重複打擾。",
    },
    {
      view: "health",
      target: "#health-overview",
      title: "健康分析",
      body: "這裡彙整長者的活躍度、情緒與認知關注等指標。點左側長者列表中的某一位，右側會顯示完整的生理 / 心理 / 情緒分析。",
    },
    {
      view: "tasks",
      target: "#view-tasks .panel",
      title: "日常任務追蹤",
      body: "吃藥、喝水、運動等任務會由長者拍照打卡，系統用 AI 影像協助確認。「等待查看」的任務可以由您再確認一次。",
    },
    {
      view: "users",
      target: "#view-users .list-section",
      title: "使用者帳戶管理",
      body: "帳戶資料來自後端資料庫，需貼上管理者權杖才會載入。為保護個資，Email 會遮蔽，且不顯示密碼或驗證碼。",
    },
    {
      view: "products",
      target: "#view-products .list-section",
      title: "商品管理",
      body: "在這裡為長照商城上架商品：填寫名稱、分類、價格、庫存、所屬長照中心與平台抽成。上架中的商品會出現在長者端 App 的照護用品商城。",
    },
    {
      view: "orders",
      target: "#view-orders .list-section",
      title: "訂單管理",
      body: "長者在 App 下單後，訂單會出現在這裡。點開可看商品明細、總金額、平台抽成與長照中心實收，並更新「待處理 / 已確認 / 配送中 / 已完成」等狀態。",
    },
    {
      view: "alerts",
      target: ".settings",
      title: "連線設定",
      body: "用手機或其他電腦連線時，展開這裡把後端位址改成「http://<Mac區網IP>:3001/api」即可。設定會記在本機瀏覽器。",
    },
    {
      view: "alerts",
      target: null,
      title: "就這樣，開始使用吧！",
      body: "隨時可以點右上角的「💡 使用說明」再看一次這份導覽。祝您使用順利，陪伴長者更安心。",
    },
  ];

  var tour = {
    root: null,
    spot: null,
    tooltip: null,
    index: 0,
    startView: "alerts",
    onKey: null,
    onResize: null,
  };

  function activeViewName() {
    if (elH.viewHealth && !elH.viewHealth.classList.contains("hidden")) {
      return "health";
    }
    if (elT.viewTasks && !elT.viewTasks.classList.contains("hidden")) {
      return "tasks";
    }
    if (elU.viewUsers && !elU.viewUsers.classList.contains("hidden")) {
      return "users";
    }
    return "alerts";
  }

  function buildTourDom() {
    var root = document.createElement("div");
    root.className = "tour-root tour-hidden";
    root.setAttribute("role", "dialog");
    root.setAttribute("aria-modal", "true");
    root.setAttribute("aria-label", "使用說明導覽");

    var backdrop = document.createElement("div");
    backdrop.className = "tour-backdrop";

    var spot = document.createElement("div");
    spot.className = "tour-spot";

    var skip = document.createElement("button");
    skip.type = "button";
    skip.className = "tour-skip";
    skip.textContent = "略過導覽";
    skip.addEventListener("click", endTour);

    var tooltip = document.createElement("div");
    tooltip.className = "tour-tooltip";

    root.appendChild(backdrop);
    root.appendChild(spot);
    root.appendChild(skip);
    root.appendChild(tooltip);
    document.body.appendChild(root);

    tour.root = root;
    tour.spot = spot;
    tour.tooltip = tooltip;
  }

  function renderTooltip(step, index) {
    var dots = "";
    for (var i = 0; i < TOUR_STEPS.length; i++) {
      dots += '<span class="tour-dot' + (i === index ? " is-active" : "") + '"></span>';
    }
    var isLast = index === TOUR_STEPS.length - 1;
    var isFirst = index === 0;
    tour.tooltip.innerHTML =
      '<div class="tour-tip-step">第 ' +
      (index + 1) +
      " / " +
      TOUR_STEPS.length +
      " 步</div>" +
      '<h3 class="tour-tip-title">' +
      escapeHtml(step.title) +
      "</h3>" +
      '<p class="tour-tip-body">' +
      escapeHtml(step.body) +
      "</p>" +
      '<div class="tour-tip-foot">' +
      '<div class="tour-progress">' +
      dots +
      "</div>" +
      '<div class="tour-actions">' +
      (isFirst
        ? ""
        : '<button type="button" class="tour-btn" id="tour-prev">上一步</button>') +
      '<button type="button" class="tour-btn tour-btn-primary" id="tour-next">' +
      (isLast ? "完成" : "下一步") +
      "</button>" +
      "</div>" +
      "</div>";

    var prevBtn = document.getElementById("tour-prev");
    if (prevBtn) prevBtn.addEventListener("click", function () { gotoStep(index - 1); });
    var nextBtn = document.getElementById("tour-next");
    if (nextBtn) {
      nextBtn.addEventListener("click", function () {
        if (isLast) endTour();
        else gotoStep(index + 1);
      });
    }
  }

  function positionSpotlight(step) {
    var spot = tour.spot;
    var tip = tour.tooltip;
    var vw = window.innerWidth;
    var vh = window.innerHeight;
    var targetEl = step.target ? document.querySelector(step.target) : null;

    if (!targetEl) {
      // 置中（歡迎 / 結束）：遮罩全暗、卡片置中。
      spot.classList.add("tour-spot-center");
      tip.style.left = Math.max(18, (vw - tip.offsetWidth) / 2) + "px";
      tip.style.top = Math.max(18, (vh - tip.offsetHeight) / 2) + "px";
      return;
    }

    spot.classList.remove("tour-spot-center");
    var pad = 8;
    var r = targetEl.getBoundingClientRect();
    var top = Math.max(pad, r.top - pad);
    var left = Math.max(pad, r.left - pad);
    var width = Math.min(vw - left - pad, r.width + pad * 2);
    var height = r.height + pad * 2;
    spot.style.top = top + "px";
    spot.style.left = left + "px";
    spot.style.width = width + "px";
    spot.style.height = height + "px";

    // 卡片優先放在高亮下方，空間不夠就放上方，再不夠就靠底部。
    var tipW = tip.offsetWidth || 320;
    var tipH = tip.offsetHeight || 160;
    var tipLeft = Math.min(Math.max(pad, left), vw - tipW - pad);
    var below = top + height + 14;
    var tipTop;
    if (below + tipH <= vh - pad) {
      tipTop = below;
    } else if (top - tipH - 14 >= pad) {
      tipTop = top - tipH - 14;
    } else {
      tipTop = Math.max(pad, vh - tipH - pad);
    }
    tip.style.left = tipLeft + "px";
    tip.style.top = tipTop + "px";
  }

  function gotoStep(index) {
    if (index < 0 || index >= TOUR_STEPS.length) return;
    tour.index = index;
    var step = TOUR_STEPS[index];
    showView(step.view);
    renderTooltip(step, index);
    // 切分頁 / 懶載入後讓版面安定，再量測定位。
    var targetEl = step.target ? document.querySelector(step.target) : null;
    if (targetEl && targetEl.scrollIntoView) {
      targetEl.scrollIntoView({ block: "center", behavior: "auto" });
    }
    window.requestAnimationFrame(function () {
      setTimeout(function () {
        positionSpotlight(step);
      }, 60);
    });
  }

  function startTour() {
    if (!tour.root) buildTourDom();
    tour.startView = activeViewName();
    tour.root.classList.remove("tour-hidden");

    tour.onKey = function (e) {
      if (e.key === "Escape") {
        e.stopPropagation();
        endTour();
      } else if (e.key === "ArrowRight") {
        gotoStep(tour.index + 1);
      } else if (e.key === "ArrowLeft") {
        gotoStep(tour.index - 1);
      }
    };
    tour.onResize = function () {
      positionSpotlight(TOUR_STEPS[tour.index]);
    };
    document.addEventListener("keydown", tour.onKey, true);
    window.addEventListener("resize", tour.onResize);
    window.addEventListener("scroll", tour.onResize, true);

    gotoStep(0);
  }

  function endTour() {
    if (tour.root) tour.root.classList.add("tour-hidden");
    if (tour.onKey) document.removeEventListener("keydown", tour.onKey, true);
    if (tour.onResize) {
      window.removeEventListener("resize", tour.onResize);
      window.removeEventListener("scroll", tour.onResize, true);
    }
    try {
      localStorage.setItem(TOUR_DONE_KEY, "1");
    } catch (err) {
      /* localStorage 不可用時忽略，不影響導覽 */
    }
    // 回到使用者開始導覽前所在的分頁。
    showView(tour.startView || "alerts");
  }

  function setupGuidedTour() {
    var startBtn = document.getElementById("tour-start");
    if (startBtn) startBtn.addEventListener("click", startTour);
    // 第一次造訪自動播放一次（資料載入後稍等，畫面比較穩定）。
    var done = "";
    try {
      done = localStorage.getItem(TOUR_DONE_KEY) || "";
    } catch (err) {
      done = "";
    }
    if (!done) {
      setTimeout(startTour, 900);
    }
  }

  // ---- init ----
  // ===================================================================
  // CR-0032 長照商品商城：商品管理 + 訂單管理
  // ===================================================================

  var productsCache = [];
  var ordersCache = [];

  // 帶 Admin token 的 JSON 寫入 headers。
  function adminJsonHeaders() {
    var h = { "Content-Type": "application/json" };
    var token = getAdminToken();
    if (token) h.Authorization = "Bearer " + token;
    return h;
  }

  function setProductsStatus(msg, kind) {
    if (!elP.status) return;
    elP.status.textContent = msg || "";
    elP.status.classList.toggle("error", kind === "error");
  }

  function loadProducts() {
    var category = elP.filter ? elP.filter.value : "";
    // status=all：管理端要同時看到上架 / 下架商品。
    var url = marketplaceUrl("/products?status=all");
    if (category) url += "&category=" + encodeURIComponent(category);
    setProductsStatus("商品載入中…", "");
    fetch(url)
      .then(function (r) {
        if (!r.ok) throw new Error("HTTP " + r.status);
        return r.json();
      })
      .then(function (body) {
        if (!body || body.ok !== true || !Array.isArray(body.products)) {
          throw new Error("bad_payload");
        }
        productsCache = body.products;
        renderProducts(body.products);
        setProductsStatus("", "");
      })
      .catch(function () {
        if (elP.tableWrap) elP.tableWrap.innerHTML = "";
        if (elP.count) elP.count.textContent = "";
        setProductsStatus("目前連不到後端，待會再重新整理看看。", "error");
      });
  }

  function productStatusBadge(status) {
    var on = status === "active";
    return (
      '<span class="badge status ' +
      (on ? "status-resolved" : "status-off") +
      '">' +
      (on ? "上架中" : "已下架") +
      "</span>"
    );
  }

  function renderProducts(products) {
    if (elP.count) elP.count.textContent = "共 " + products.length + " 筆";
    if (!products.length) {
      elP.tableWrap.innerHTML =
        '<p class="empty">目前沒有商品，點右上角「新增商品」開始上架。</p>';
      return;
    }
    var rows = products
      .map(function (p) {
        return (
          "<tr>" +
          "<td>" + escapeHtml(p.name || "—") + "</td>" +
          "<td>" + escapeHtml(p.category || "—") + "</td>" +
          "<td>" + escapeHtml(p.center_name || "—") + "</td>" +
          "<td>" + formatMoney(p.price) + "</td>" +
          "<td>" + (Number(p.stock) || 0) + "</td>" +
          "<td>" + Math.round((Number(p.commission_rate) || 0) * 100) + "%</td>" +
          "<td>" + productStatusBadge(p.status) + "</td>" +
          '<td class="row-actions">' +
          '<button class="btn btn-sm" data-action="edit" data-id="' +
          escapeHtml(p.id) +
          '">編輯</button>' +
          '<button class="btn btn-sm" data-action="toggle" data-id="' +
          escapeHtml(p.id) +
          '" data-status="' +
          escapeHtml(p.status) +
          '">' +
          (p.status === "active" ? "下架" : "上架") +
          "</button>" +
          "</td>" +
          "</tr>"
        );
      })
      .join("");
    elP.tableWrap.innerHTML =
      '<table class="users-table"><thead><tr>' +
      "<th>商品</th><th>分類</th><th>長照中心</th><th>價格</th><th>庫存</th><th>抽成</th><th>狀態</th><th>操作</th>" +
      "</tr></thead><tbody>" +
      rows +
      "</tbody></table>";

    var btns = elP.tableWrap.querySelectorAll("button[data-action]");
    for (var i = 0; i < btns.length; i++) {
      btns[i].addEventListener("click", onProductAction);
    }
  }

  function onProductAction(e) {
    var btn = e.currentTarget;
    var id = btn.getAttribute("data-id");
    var action = btn.getAttribute("data-action");
    if (action === "edit") {
      var product = null;
      for (var i = 0; i < productsCache.length; i++) {
        if (productsCache[i].id === id) {
          product = productsCache[i];
          break;
        }
      }
      openProductForm(product);
    } else if (action === "toggle") {
      var status = btn.getAttribute("data-status");
      toggleProductStatus(id, status === "active" ? "inactive" : "active");
    }
  }

  function productFormError(msg) {
    if (!elP.formStatus) return;
    elP.formStatus.textContent = msg;
    elP.formStatus.classList.add("error");
  }

  function openProductForm(product) {
    if (elP.form) elP.form.reset();
    if (elP.formStatus) {
      elP.formStatus.textContent = "";
      elP.formStatus.classList.remove("error");
    }
    if (product) {
      elP.formTitle.textContent = "編輯商品";
      elP.fId.value = product.id || "";
      elP.fName.value = product.name || "";
      elP.fCategory.value = product.category || "照護用品";
      elP.fDescription.value = product.description || "";
      elP.fCenterName.value = product.center_name || "";
      elP.fCenterId.value = product.center_id || "";
      elP.fPrice.value = product.price != null ? product.price : "";
      elP.fStock.value = product.stock != null ? product.stock : "";
      elP.fCommission.value =
        product.commission_rate != null ? product.commission_rate : "";
      elP.fStatus.value = product.status || "active";
      elP.fImage.value = product.image_url || "";
    } else {
      elP.formTitle.textContent = "新增商品";
      elP.fId.value = "";
      elP.fCategory.value = "照護用品";
      elP.fStatus.value = "active";
      elP.fCommission.value = "0.10";
    }
    elP.overlay.classList.remove("hidden");
  }

  function closeProductForm() {
    if (elP.overlay) elP.overlay.classList.add("hidden");
  }

  function submitProductForm(e) {
    if (e) e.preventDefault();
    if (!getAdminToken()) {
      productFormError("請先在上方輸入管理者權杖（Admin Token）。");
      return;
    }
    var name = (elP.fName.value || "").trim();
    if (!name) {
      productFormError("請填寫商品名稱。");
      return;
    }
    var id = (elP.fId.value || "").trim();
    var payload = {
      name: name,
      category: elP.fCategory.value,
      description: (elP.fDescription.value || "").trim(),
      center_name: (elP.fCenterName.value || "").trim(),
      center_id: (elP.fCenterId.value || "").trim(),
      price: Number(elP.fPrice.value) || 0,
      stock: Number(elP.fStock.value) || 0,
      commission_rate: Number(elP.fCommission.value) || 0,
      status: elP.fStatus.value,
      image_url: (elP.fImage.value || "").trim(),
    };
    var method = id ? "PUT" : "POST";
    var url = id
      ? adminUrl("/marketplace/products/" + encodeURIComponent(id))
      : adminUrl("/marketplace/products");
    if (elP.formStatus) elP.formStatus.textContent = "儲存中…";
    fetch(url, {
      method: method,
      headers: adminJsonHeaders(),
      body: JSON.stringify(payload),
    })
      .then(function (r) {
        if (r.status === 401 || r.status === 403) throw new Error("unauthorized");
        if (!r.ok) throw new Error("HTTP " + r.status);
        return r.json();
      })
      .then(function () {
        closeProductForm();
        loadProducts();
      })
      .catch(function (err) {
        if (err && err.message === "unauthorized") {
          productFormError("管理者權杖無效或未授權。");
        } else {
          productFormError("儲存沒成功，請稍後再試。");
        }
      });
  }

  function toggleProductStatus(id, nextStatus) {
    if (!getAdminToken()) {
      setProductsStatus("請先輸入管理者權杖（Admin Token）。", "error");
      return;
    }
    fetch(adminUrl("/marketplace/products/" + encodeURIComponent(id) + "/status"), {
      method: "PATCH",
      headers: adminJsonHeaders(),
      body: JSON.stringify({ status: nextStatus }),
    })
      .then(function (r) {
        if (r.status === 401 || r.status === 403) throw new Error("unauthorized");
        if (!r.ok) throw new Error("HTTP " + r.status);
        return r.json();
      })
      .then(function () {
        loadProducts();
      })
      .catch(function (err) {
        if (err && err.message === "unauthorized") {
          setProductsStatus("管理者權杖無效或未授權。", "error");
        } else {
          setProductsStatus("狀態更新沒成功，請稍後再試。", "error");
        }
      });
  }

  // ---- 訂單管理 ----

  function setOrdersStatus(msg, kind) {
    if (!elO.status) return;
    elO.status.textContent = msg || "";
    elO.status.classList.toggle("error", kind === "error");
  }

  function loadOrders() {
    if (!getAdminToken()) {
      setOrdersStatus("請先輸入管理者權杖（Admin Token），再重新整理。", "error");
      if (elO.list) elO.list.innerHTML = "";
      if (elO.count) elO.count.textContent = "";
      return;
    }
    var status = elO.filter ? elO.filter.value : "";
    var url = adminUrl("/marketplace/orders");
    if (status) url += "?status=" + encodeURIComponent(status);
    setOrdersStatus("訂單載入中…", "");
    fetch(url, { headers: adminAuthHeaders() })
      .then(function (r) {
        if (r.status === 401 || r.status === 403) throw new Error("unauthorized");
        if (!r.ok) throw new Error("HTTP " + r.status);
        return r.json();
      })
      .then(function (body) {
        if (!body || body.ok !== true || !Array.isArray(body.orders)) {
          throw new Error("bad_payload");
        }
        ordersCache = body.orders;
        renderOrders(body.orders);
        setOrdersStatus("", "");
      })
      .catch(function (err) {
        if (elO.list) elO.list.innerHTML = "";
        if (elO.count) elO.count.textContent = "";
        if (err && err.message === "unauthorized") {
          setOrdersStatus("管理者權杖無效或未授權。", "error");
        } else {
          setOrdersStatus("目前連不到後端，待會再重新整理看看。", "error");
        }
      });
  }

  function orderStatusBadge(status) {
    return (
      '<span class="badge status order-' +
      escapeHtml(status) +
      '">' +
      escapeHtml(ORDER_STATUS_LABELS[status] || status) +
      "</span>"
    );
  }

  function renderOrders(orders) {
    if (elO.count) elO.count.textContent = "共 " + orders.length + " 筆";
    if (!orders.length) {
      elO.list.innerHTML = '<p class="empty">目前沒有符合條件的訂單。</p>';
      return;
    }
    elO.list.innerHTML = orders
      .map(function (o) {
        var itemCount = Array.isArray(o.items) ? o.items.length : 0;
        return (
          '<div class="order-row" data-id="' +
          escapeHtml(o.id) +
          '">' +
          '<div class="order-row-main">' +
          '<span class="order-elder">' +
          escapeHtml(o.elder_name || "長者") +
          "</span>" +
          '<span class="order-center">' +
          escapeHtml(o.center_name || "—") +
          "</span>" +
          '<span class="order-items-count">' +
          itemCount +
          " 項商品</span>" +
          "</div>" +
          '<div class="order-row-meta">' +
          orderStatusBadge(o.status) +
          '<span class="order-amount">' +
          formatMoney(o.total_amount) +
          "</span>" +
          "</div>" +
          "</div>"
        );
      })
      .join("");
    var rows = elO.list.querySelectorAll(".order-row");
    for (var i = 0; i < rows.length; i++) {
      rows[i].addEventListener("click", function () {
        openOrderDetail(this.getAttribute("data-id"));
      });
    }
  }

  function openOrderDetail(id) {
    var order = null;
    for (var i = 0; i < ordersCache.length; i++) {
      if (ordersCache[i].id === id) {
        order = ordersCache[i];
        break;
      }
    }
    if (!order) return;
    renderOrderDetail(order);
    elO.overlay.classList.remove("hidden");
  }

  function closeOrderDetail() {
    if (elO.overlay) elO.overlay.classList.add("hidden");
  }

  function renderOrderDetail(order) {
    var items = Array.isArray(order.items) ? order.items : [];
    var itemRows = items
      .map(function (it) {
        return (
          "<tr>" +
          "<td>" + escapeHtml(it.product_name || "—") + "</td>" +
          "<td>" + (Number(it.quantity) || 0) + "</td>" +
          "<td>" + formatMoney(it.unit_price) + "</td>" +
          "<td>" + formatMoney(it.subtotal) + "</td>" +
          "</tr>"
        );
      })
      .join("");

    var statusOptions = ORDER_STATUS_FLOW.map(function (s) {
      return (
        '<option value="' +
        s +
        '"' +
        (s === order.status ? " selected" : "") +
        ">" +
        ORDER_STATUS_LABELS[s] +
        "</option>"
      );
    }).join("");

    var commissionPct = Math.round((Number(order.commission_rate) || 0) * 100);

    elO.detailBody.innerHTML =
      '<div class="detail-row"><span class="detail-key">購買人 / 長者</span><span class="detail-val">' +
      escapeHtml(order.elder_name || "—") +
      "</span></div>" +
      '<div class="detail-row"><span class="detail-key">長照中心</span><span class="detail-val">' +
      escapeHtml(order.center_name || "—") +
      "</span></div>" +
      '<table class="users-table order-items-table"><thead><tr><th>商品</th><th>數量</th><th>單價</th><th>小計</th></tr></thead><tbody>' +
      itemRows +
      "</tbody></table>" +
      '<div class="order-money">' +
      '<div class="order-money-row"><span>商品總金額</span><strong>' +
      formatMoney(order.total_amount) +
      "</strong></div>" +
      '<div class="order-money-row"><span>平台抽成（' +
      commissionPct +
      '%）</span><strong>' +
      formatMoney(order.commission_amount) +
      "</strong></div>" +
      '<div class="order-money-row order-money-net"><span>長照中心實收</span><strong>' +
      formatMoney(order.center_revenue) +
      "</strong></div>" +
      "</div>" +
      '<div class="form-field"><label class="field-label" for="order-status-select">訂單狀態</label><select id="order-status-select" class="select">' +
      statusOptions +
      "</select></div>" +
      '<div class="form-field"><label class="field-label" for="order-delivery-note">配送備註</label><textarea id="order-delivery-note" class="text-input" rows="2">' +
      escapeHtml(order.delivery_note || "") +
      "</textarea></div>" +
      '<p id="order-detail-status" class="status-message"></p>' +
      '<div class="form-actions"><button type="button" id="order-save" class="btn btn-primary">儲存更新</button></div>';

    var saveBtn = document.getElementById("order-save");
    if (saveBtn) {
      saveBtn.addEventListener("click", function () {
        updateOrderFromDetail(order.id);
      });
    }
  }

  function updateOrderFromDetail(id) {
    var statusSel = document.getElementById("order-status-select");
    var noteEl = document.getElementById("order-delivery-note");
    var statusMsg = document.getElementById("order-detail-status");
    if (!getAdminToken()) {
      if (statusMsg) {
        statusMsg.textContent = "請先輸入管理者權杖。";
        statusMsg.classList.add("error");
      }
      return;
    }
    var payload = {
      status: statusSel ? statusSel.value : "pending",
      deliveryNote: noteEl ? noteEl.value : "",
    };
    if (statusMsg) {
      statusMsg.textContent = "儲存中…";
      statusMsg.classList.remove("error");
    }
    fetch(adminUrl("/marketplace/orders/" + encodeURIComponent(id) + "/status"), {
      method: "PATCH",
      headers: adminJsonHeaders(),
      body: JSON.stringify(payload),
    })
      .then(function (r) {
        if (r.status === 401 || r.status === 403) throw new Error("unauthorized");
        if (!r.ok) throw new Error("HTTP " + r.status);
        return r.json();
      })
      .then(function () {
        closeOrderDetail();
        loadOrders();
      })
      .catch(function (err) {
        if (statusMsg) {
          statusMsg.textContent =
            err && err.message === "unauthorized"
              ? "管理者權杖無效或未授權。"
              : "更新沒成功，請稍後再試。";
          statusMsg.classList.add("error");
        }
      });
  }

  // 把目前 admin token 同步到所有分頁的權杖輸入框，存一次三頁通用。
  function syncAdminTokenInputs() {
    var token = getAdminToken();
    if (elU.adminToken) elU.adminToken.value = token;
    if (elP.adminToken) elP.adminToken.value = token;
    if (elO.adminToken) elO.adminToken.value = token;
  }

  function saveAdminTokenFrom(inputEl, reload) {
    localStorage.setItem(ADMIN_TOKEN_KEY, (inputEl.value || "").trim());
    syncAdminTokenInputs();
    if (reload) reload();
  }

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
      if (e.key === "Escape") {
        closeDetail();
        closeProductForm();
        closeOrderDetail();
      }
    });

    // 健康分析分頁：切到健康分析才載入（懶載入）。
    elH.tabAlerts.addEventListener("click", function () {
      showView("alerts");
    });
    elH.tabHealth.addEventListener("click", function () {
      showView("health");
    });
    elH.healthRefresh.addEventListener("click", function () {
      loadHealthOverview();
      loadElderList();
    });

    // CR-0025 日常任務追蹤分頁。
    if (elT.tabTasks) {
      elT.tabTasks.addEventListener("click", function () {
        showView("tasks");
      });
    }
    if (elT.tasksRefresh) {
      elT.tasksRefresh.addEventListener("click", loadDailyTasks);
    }
    if (elT.tasksFilter) {
      elT.tasksFilter.addEventListener("change", loadDailyTasks);
    }

    // CR-0029 使用者管理分頁。
    if (elU.tabUsers) {
      elU.tabUsers.addEventListener("click", function () {
        showView("users");
      });
    }
    if (elU.adminToken) {
      elU.adminToken.value = getAdminToken();
    }
    if (elU.saveAdminToken) {
      elU.saveAdminToken.addEventListener("click", function () {
        saveAdminTokenFrom(elU.adminToken, loadUsers);
      });
    }
    if (elU.usersRefresh) {
      elU.usersRefresh.addEventListener("click", loadUsers);
    }

    // CR-0032 商品管理分頁。
    if (elP.tabProducts) {
      elP.tabProducts.addEventListener("click", function () {
        showView("products");
      });
    }
    if (elP.refresh) elP.refresh.addEventListener("click", loadProducts);
    if (elP.filter) elP.filter.addEventListener("change", loadProducts);
    if (elP.add) {
      elP.add.addEventListener("click", function () {
        openProductForm(null);
      });
    }
    if (elP.saveToken) {
      elP.saveToken.addEventListener("click", function () {
        saveAdminTokenFrom(elP.adminToken, loadProducts);
      });
    }
    if (elP.form) elP.form.addEventListener("submit", submitProductForm);
    if (elP.formClose) elP.formClose.addEventListener("click", closeProductForm);
    if (elP.formCancel) elP.formCancel.addEventListener("click", closeProductForm);
    if (elP.overlay) {
      elP.overlay.addEventListener("click", function (e) {
        if (e.target === elP.overlay) closeProductForm();
      });
    }

    // CR-0032 訂單管理分頁。
    if (elO.tabOrders) {
      elO.tabOrders.addEventListener("click", function () {
        showView("orders");
      });
    }
    if (elO.refresh) elO.refresh.addEventListener("click", loadOrders);
    if (elO.filter) elO.filter.addEventListener("change", loadOrders);
    if (elO.saveToken) {
      elO.saveToken.addEventListener("click", function () {
        saveAdminTokenFrom(elO.adminToken, loadOrders);
      });
    }
    if (elO.detailClose) elO.detailClose.addEventListener("click", closeOrderDetail);
    if (elO.overlay) {
      elO.overlay.addEventListener("click", function (e) {
        if (e.target === elO.overlay) closeOrderDetail();
      });
    }
    syncAdminTokenInputs();

    setupGuidedTour();
    loadAlerts();
  }

  init();
})();
