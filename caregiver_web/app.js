// 長照照護管理後台前端邏輯。
// 讀取後端已保存的 Care Alert / analytics，並以 Firebase caregiver login
// 或 super_admin token 帶 Authorization header。全部資料來自後端 API，沒有任何假資料。

(function () {
  "use strict";

  var API_BASE_KEY = "caregiver_api_base";
  // 後端 API 位址預設使用「同源相對路徑」，正式部署時 caregiver_web 與後端同網域
  // 或經反向代理即可直接運作；不把 localhost / 127.0.0.1 硬編為正式預設。
  // 部署正式後端時，請於 index.html（或注入的 config.js）設定
  // window.APP_CONFIG.apiBaseUrl = "https://api.your-domain.com/api"。
  // 本機開發若後端在另一個 port（例如 3001），可在頁面「連線設定」輸入後端位址。
  var DEFAULT_API_BASE = "/api";
  // CR-0029：管理者（super_admin）權杖只存在本機 localStorage，不寫死、不進 Git。
  // 這是「最高權限」共享 token（ADMIN_API_TOKEN），可檢視全部住民。
  var ADMIN_TOKEN_KEY = "caregiver_admin_token";
  // CR-0042：照護人員（caregiver）登入權杖獨立儲存，與 super_admin token 分開，
  // 絕不寫入 ADMIN_TOKEN_KEY。caregiver 只會看到被指派的住民。
  var CAREGIVER_TOKEN_KEY = "caregiver_login_token";
  // CR-0042：目前身分模式（'super_admin' | 'caregiver' | 'none'）。
  var AUTH_MODE_KEY = "caregiver_auth_mode";
  var FIREBASE_APP_MODULE_URL =
    "https://www.gstatic.com/firebasejs/10.12.4/firebase-app.js";
  var FIREBASE_AUTH_MODULE_URL =
    "https://www.gstatic.com/firebasejs/10.12.4/firebase-auth.js";

  // CR-0042：友善文案（白話、非工程術語、不顯示完整 token / stack）。
  var EMPTY_CAREGIVER_MSG =
    "目前尚未被指派可查看的住民。請聯絡管理者確認權限設定。";
  var SESSION_EXPIRED_MSG = "登入已失效，請重新登入";
  var FORBIDDEN_MSG = "目前帳號沒有權限查看此資料";
  var NEED_LOGIN_MSG = "請先在上方選擇身分並登入。";
  // CR-0044：provisioning（super_admin-only）空狀態文案。
  var EMPTY_CAREGIVERS_MSG = "目前尚無照護人員";
  var EMPTY_ASSIGNMENTS_MSG = "目前尚無住民授權指派";
  var NEED_ADMIN_MSG = "請先以管理者身分登入（在上方選「管理者」並貼上管理者權杖）。";

  // CR-0044：授權角色對外文案（對齊後端 migration 013 真值 primary|secondary|viewer）。
  var ROLE_LABELS = {
    primary: "主要照護",
    secondary: "備援照護",
    viewer: "唯讀",
  };

  // CR-0042：身分狀態。語意清楚區分 super_admin / caregiver / none。
  // displayName 不在前端偽造（未做 Firebase 驗證），維持 null。
  var authState = {
    authMode: "none",
    token: null,
    displayName: null,
    role: null,
  };
  var firebaseAuthState = {
    loading: false,
    ready: false,
    auth: null,
    modules: null,
    lastUid: null,
  };
  // 401 之後設為 true，停止重複狂打受保護 API，直到使用者重新登入。
  var sessionInvalid = false;

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
  // 部署時注入的設定（index.html 內 window.APP_CONFIG 或獨立 config.js）。
  function configuredApiBase() {
    var cfg = (typeof window !== "undefined" && window.APP_CONFIG) || {};
    return normalizeBase(cfg.apiBaseUrl);
  }

  function mergeAppConfig(nextConfig) {
    if (!nextConfig || typeof nextConfig !== "object") return;
    var current = (typeof window !== "undefined" && window.APP_CONFIG) || {};
    window.APP_CONFIG = Object.assign({}, current, nextConfig, {
      firebase: Object.assign({}, current.firebase || {}, nextConfig.firebase || {}),
      featureFlags: Object.assign(
        {},
        current.featureFlags || {},
        nextConfig.featureFlags || {}
      ),
    });
  }

  function loadRuntimeConfig() {
    var url = getApiBase() + "/caregiver-web/config";
    return fetch(url)
      .then(function (r) {
        if (!r.ok) throw new Error("config_unavailable");
        return r.json();
      })
      .then(function (body) {
        if (body && body.ok === true && body.config) {
          mergeAppConfig(body.config);
        }
      })
      .catch(function () {
        // 靜默退回 index.html 內的 APP_CONFIG；登入區會用白話提示設定尚未完成。
      });
  }

  // 功能旗標（CR-0056）：marketplace（商品 / 訂單）與 dailyCareTasks（今日任務）
  // 分頁能力保留，但「正式版預設隱藏入口」。未提供 featureFlags 或對應旗標時，
  // 一律視為關閉（隱藏）；只有明確設成 true 才顯示。純前端隱藏分頁，
  // 不影響後端 admin API 行為（防禦縱深，非權限控管）。
  function featureEnabled(name) {
    var cfg = (typeof window !== "undefined" && window.APP_CONFIG) || {};
    var flags = cfg.featureFlags || {};
    return flags[name] === true;
  }

  // 隱藏一個分頁按鈕（保留 DOM / 功能，只移除入口）。
  function hideTabButton(tabEl) {
    if (!tabEl) return;
    tabEl.classList.add("hidden");
    tabEl.setAttribute("aria-hidden", "true");
  }

  // 依 featureFlags 隱藏對應分頁入口（marketplace / dailyCareTasks）。
  function applyFeatureFlags() {
    if (!featureEnabled("marketplace")) {
      hideTabButton(elP && elP.tabProducts);
      hideTabButton(elO && elO.tabOrders);
    }
    if (!featureEnabled("dailyCareTasks")) {
      hideTabButton(elT && elT.tabTasks);
    }
  }

  // API base URL 解析順序（擇先非空者）：
  // 1. 使用者在「連線設定」手動覆寫（localStorage，dev / 區網用）。
  // 2. 部署注入的 window.APP_CONFIG.apiBaseUrl（正式後端位址）。
  // 3. DEFAULT_API_BASE 同源相對路徑 "/api"（無 localhost 硬編）。
  function getApiBase() {
    var stored = normalizeBase(localStorage.getItem(API_BASE_KEY));
    if (stored) return stored;
    var configured = configuredApiBase();
    if (configured) return configured;
    return DEFAULT_API_BASE;
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

  function petTypeLabel(value) {
    switch (value) {
      case "dog":
        return "狗狗";
      case "guinea_pig":
        return "天竺鼠";
      case "fox":
        return "狐狸";
      case "mochi":
        return "麻吉";
      default:
        return value || "—";
    }
  }

  function petVisualStyleLabel(value) {
    switch (value) {
      case "cute":
        return "Q版";
      case "realistic":
        return "真實版";
      default:
        return value || "—";
    }
  }

  function petGrowthStageLabel(value) {
    switch (value) {
      case "baby":
        return "幼年";
      case "young":
        return "成長中";
      case "adult":
        return "成年";
      default:
        return value || "—";
    }
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
    el.list.innerHTML = "";
    if (
      !ensureCanFetch(function (msg) {
        resetStats();
        setListCount(0);
        setStatus(msg, true);
      })
    ) {
      return;
    }
    setStatus("載入中…", false);
    var url = getApiBase() + "/care-alerts" + buildQuery();
    fetch(url, { headers: authHeaders() })
      .then(function (res) {
        if (res.status === 401) {
          handleSessionExpired();
          throw new Error("session_expired");
        }
        if (res.status === 403) throw new Error("forbidden");
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
          // caregiver 無授權住民時，後端回空陣列 → 友善空狀態（不顯示全部）。
          setStatus(
            isCaregiverMode()
              ? EMPTY_CAREGIVER_MSG
              : "目前一切平安，沒有需要關心的提醒 🌿",
            false
          );
          return;
        }
        setStatus("", false);
        renderList(data.alerts);
      })
      .catch(function (err) {
        resetStats();
        setListCount(0);
        if (err && err.message === "session_expired") {
          setStatus(SESSION_EXPIRED_MSG, true);
          return;
        }
        if (err && err.message === "forbidden") {
          setStatus(FORBIDDEN_MSG, true);
          return;
        }
        setStatus("暫時連不上後端，請確認服務是否已啟動後再重新整理", true);
      })
      // 登入後預設落在照護提醒分頁；此處載入結束即清掉登入過場提示，避免卡住。
      .finally(clearAuthLoadingMessage);
  }

  function openDetail(id) {
    if (!id) return;
    if (sessionInvalid || !hasActiveToken()) {
      handleSessionExpired();
      return;
    }
    el.detailBody.innerHTML = '<p class="status-message">載入中…</p>';
    el.overlay.classList.remove("hidden");
    fetch(getApiBase() + "/care-alerts/" + encodeURIComponent(id), {
      headers: authHeaders(),
    })
      .then(function (res) {
        if (res.status === 401) {
          handleSessionExpired();
          throw new Error("session_expired");
        }
        if (res.status === 403) throw new Error("forbidden");
        if (!res.ok) throw new Error("HTTP " + res.status);
        return res.json();
      })
      .then(function (data) {
        if (!data || data.success !== true || !data.alert) {
          throw new Error("unexpected response");
        }
        renderDetail(data.alert);
      })
      .catch(function (err) {
        if (err && err.message === "session_expired") {
          el.detailBody.innerHTML =
            '<p class="status-message error">' + SESSION_EXPIRED_MSG + "</p>";
          return;
        }
        if (err && err.message === "forbidden") {
          // 跨住民 / 無權限：顯示權限不足，不清 token。
          el.detailBody.innerHTML =
            '<p class="status-message error">' + FORBIDDEN_MSG + "</p>";
          return;
        }
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
      headers: authJsonHeaders(),
      body: JSON.stringify({ status: status }),
    })
      .then(function (res) {
        if (res.status === 401) {
          handleSessionExpired();
          throw new Error("session_expired");
        }
        if (res.status === 403) throw new Error("forbidden");
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
      .catch(function (err) {
        Array.prototype.forEach.call(buttons, function (b) {
          b.disabled = false;
        });
        if (err && err.message === "session_expired") {
          setDetailMsg(SESSION_EXPIRED_MSG, true);
          return;
        }
        if (err && err.message === "forbidden") {
          setDetailMsg(FORBIDDEN_MSG, true);
          return;
        }
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

  // CR-0086 長者狀態分析 view 的元素參照與狀態。
  var elAN = {
    tab: document.getElementById("tab-analytics"),
    view: document.getElementById("view-analytics"),
    elderSelect: document.getElementById("analytics-elder"),
    rangeSelect: document.getElementById("analytics-range"),
    refresh: document.getElementById("analytics-refresh"),
    status: document.getElementById("analytics-status"),
    body: document.getElementById("analytics-body"),
  };
  var analyticsLoaded = false;
  var analyticsElderId = null;

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

  // CR-0044 照護人員管理 view（super_admin-only）元素參照。
  var elCG = {
    tab: document.getElementById("tab-caregivers"),
    view: document.getElementById("view-caregivers"),
    refresh: document.getElementById("caregivers-refresh"),
    add: document.getElementById("caregiver-add"),
    status: document.getElementById("caregivers-status"),
    count: document.getElementById("caregivers-count"),
    tableWrap: document.getElementById("caregivers-table-wrap"),
    overlay: document.getElementById("caregiver-overlay"),
    formTitle: document.getElementById("caregiver-form-title"),
    form: document.getElementById("caregiver-form"),
    formClose: document.getElementById("caregiver-form-close"),
    formCancel: document.getElementById("caregiver-form-cancel"),
    formStatus: document.getElementById("caregiver-form-status"),
    fId: document.getElementById("cgf-id"),
    fName: document.getElementById("cgf-name"),
    fEmail: document.getElementById("cgf-email"),
    fEmailHint: document.getElementById("cgf-email-hint"),
    fFirebase: document.getElementById("cgf-firebase"),
  };
  var caregiversLoaded = false;
  var caregiversCache = [];

  // CR-0044 住民授權指派 view（super_admin-only）元素參照。
  var elAS = {
    tab: document.getElementById("tab-assignments"),
    view: document.getElementById("view-assignments"),
    refresh: document.getElementById("assignments-refresh"),
    add: document.getElementById("assignment-add"),
    status: document.getElementById("assignments-status"),
    count: document.getElementById("assignments-count"),
    tableWrap: document.getElementById("assignments-table-wrap"),
    overlay: document.getElementById("assignment-overlay"),
    formTitle: document.getElementById("assignment-form-title"),
    form: document.getElementById("assignment-form"),
    formClose: document.getElementById("assignment-form-close"),
    formCancel: document.getElementById("assignment-form-cancel"),
    formStatus: document.getElementById("assignment-form-status"),
    fId: document.getElementById("asf-id"),
    fResident: document.getElementById("asf-resident"),
    fCaregiver: document.getElementById("asf-caregiver"),
    fRole: document.getElementById("asf-role"),
    save: document.getElementById("assignment-form-save"),
  };
  var assignmentsLoaded = false;

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
      analytics: { view: elAN.view, tab: elAN.tab },
      health: { view: elH.viewHealth, tab: elH.tabHealth },
      tasks: { view: elT.viewTasks, tab: elT.tabTasks },
      users: { view: elU.viewUsers, tab: elU.tabUsers },
      products: { view: elP.viewProducts, tab: elP.tabProducts },
      orders: { view: elO.viewOrders, tab: elO.tabOrders },
      caregivers: { view: elCG.view, tab: elCG.tab },
      assignments: { view: elAS.view, tab: elAS.tab },
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
    if (name === "analytics" && !analyticsLoaded) {
      analyticsLoaded = true;
      loadAnalyticsElders();
    }
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
    if (name === "caregivers" && !caregiversLoaded) {
      caregiversLoaded = true;
      loadCaregivers();
    }
    if (name === "assignments" && !assignmentsLoaded) {
      assignmentsLoaded = true;
      loadAssignments();
    }
  }

  // ---- CR-0029 使用者管理 ----

  // super_admin（最高權限）共享 token。只有 super_admin-only 端點才用它。
  function getAdminToken() {
    return (localStorage.getItem(ADMIN_TOKEN_KEY) || "").trim();
  }

  // caregiver 登入權杖（Firebase ID Token / caregiver session token），
  // 與 super_admin token 分開儲存，絕不存進 ADMIN_TOKEN_KEY。
  function getCaregiverToken() {
    return (localStorage.getItem(CAREGIVER_TOKEN_KEY) || "").trim();
  }

  function isSuperAdminMode() {
    return authState.authMode === "super_admin";
  }
  function isCaregiverMode() {
    return authState.authMode === "caregiver";
  }

  // CR-0042：依目前身分模式取出要帶的 token。
  // super_admin → super_admin token；caregiver → caregiver token；none → 空。
  function getActiveToken() {
    if (isSuperAdminMode()) return getAdminToken();
    if (isCaregiverMode()) return getCaregiverToken();
    return "";
  }
  function hasActiveToken() {
    return !!getActiveToken();
  }

  // CR-0042：統一的受驗證 API header helper（caregiver-or-admin 端點用）。
  // 依 authMode 帶正確 token；不把 token 印到 console。
  function authHeaders() {
    var token = getActiveToken();
    return token ? { Authorization: "Bearer " + token } : {};
  }
  function authJsonHeaders() {
    var h = { "Content-Type": "application/json" };
    var token = getActiveToken();
    if (token) h.Authorization = "Bearer " + token;
    return h;
  }

  // 帶 super_admin token 的 fetch headers（僅 super_admin-only 端點用：
  // /admin/users、/admin/overview、marketplace admin）。無 token 時不帶。
  function adminAuthHeaders() {
    var token = getAdminToken();
    return token ? { Authorization: "Bearer " + token } : {};
  }

  // CR-0042：從 localStorage 還原身分狀態。
  function loadAuthState() {
    var mode = (localStorage.getItem(AUTH_MODE_KEY) || "").trim();
    if (mode !== "super_admin" && mode !== "caregiver") {
      // 向後相容：舊版只有 super_admin 共享 token、無 authMode 記錄。
      mode = getAdminToken() ? "super_admin" : "none";
    }
    authState.authMode = mode;
    authState.role = mode === "none" ? null : mode;
    authState.token = mode === "none" ? null : getActiveToken();
    authState.displayName = null; // 不偽造名稱（未在前端驗證 token）。
  }

  // CR-0042：登入 = 儲存對應 token + 設定模式（caregiver token 不進 admin key）。
  function applyLogin(mode, token) {
    if (mode === "super_admin") {
      localStorage.setItem(ADMIN_TOKEN_KEY, token);
    } else if (mode === "caregiver") {
      localStorage.setItem(CAREGIVER_TOKEN_KEY, token);
    } else {
      return;
    }
    localStorage.setItem(AUTH_MODE_KEY, mode);
    sessionInvalid = false;
    loadAuthState();
    syncAdminTokenInputs();
    applyAuthModeUi();
  }

  // CR-0042：登出 = 清掉兩種 token 與模式，回到未登入。
  function logout() {
    localStorage.removeItem(ADMIN_TOKEN_KEY);
    localStorage.removeItem(CAREGIVER_TOKEN_KEY);
    localStorage.setItem(AUTH_MODE_KEY, "none");
    sessionInvalid = false;
    loadAuthState();
    syncAdminTokenInputs();
    applyAuthModeUi();
  }

  // CR-0042：受保護請求前的守門。無 token / session 失效 → 不發送請求。
  function ensureCanFetch(onBlocked) {
    if (sessionInvalid) {
      if (onBlocked) onBlocked(SESSION_EXPIRED_MSG);
      return false;
    }
    if (!hasActiveToken()) {
      if (onBlocked) onBlocked(NEED_LOGIN_MSG);
      return false;
    }
    return true;
  }

  // CR-0042：收到 401 → 標記 session 失效、提示重新登入、停止後續請求。
  function handleSessionExpired() {
    sessionInvalid = true;
    showAuthMessage(SESSION_EXPIRED_MSG, true);
    var bar = document.getElementById("auth-bar");
    if (bar && bar.scrollIntoView) {
      bar.scrollIntoView({ block: "start", behavior: "auto" });
    }
  }

  // ---- CR-0042 身分 / 登入列 ----
  var elA = {
    bar: document.getElementById("auth-bar"),
    statusValue: document.getElementById("auth-status-value"),
    modeCaregiver: document.getElementById("auth-mode-caregiver"),
    modeSuper: document.getElementById("auth-mode-super"),
    tokenInput: document.getElementById("auth-token-input"),
    login: document.getElementById("auth-login"),
    logout: document.getElementById("auth-logout"),
    hint: document.getElementById("auth-hint"),
    message: document.getElementById("auth-message"),
    firebasePanel: document.getElementById("firebase-login-panel"),
    firebaseEmail: document.getElementById("firebase-email"),
    firebasePassword: document.getElementById("firebase-password"),
    firebaseEmailLogin: document.getElementById("firebase-email-login"),
    firebaseGoogleLogin: document.getElementById("firebase-google-login"),
    firebaseStatus: document.getElementById("firebase-login-status"),
  };

  var CAREGIVER_HINT =
    "照護人員請使用 Email 或 Google 登入。若機構尚未設定 Firebase Web 登入，才使用下方登入權杖備援。登入後只會看到您被指派的住民。";
  var SUPER_ADMIN_HINT =
    "管理者權杖（ADMIN_API_TOKEN）擁有最高權限、可檢視全部住民資料，正式環境請勿提供給一般照護人員。";

  function showAuthMessage(text, isError) {
    if (!elA.message) return;
    elA.message.textContent = text || "";
    elA.message.classList.toggle("error", !!isError);
  }

  // CR-0065：登入後顯示「正在以…身分載入資料…」過場提示；資料載入流程結束後清除，
  // 避免訊息永遠卡著（過去只在登出時清除）。不蓋掉錯誤 / session 過期等紅字提示。
  function clearAuthLoadingMessage() {
    if (!elA.message) return;
    if (elA.message.classList.contains("error")) return;
    elA.message.textContent = "";
  }

  // 目前 radio 選到的模式（未選時回 none）。
  function selectedAuthMode() {
    if (elA.modeSuper && elA.modeSuper.checked) return "super_admin";
    if (elA.modeCaregiver && elA.modeCaregiver.checked) return "caregiver";
    return "none";
  }

  function updateAuthHint() {
    if (!elA.hint) return;
    var mode = selectedAuthMode();
    if (mode === "super_admin") elA.hint.textContent = SUPER_ADMIN_HINT;
    else if (mode === "caregiver") elA.hint.textContent = CAREGIVER_HINT;
    else elA.hint.textContent = CAREGIVER_HINT;
    updateFirebasePanelUi();
  }

  function updateAuthStatusUi() {
    if (elA.statusValue) {
      if (isSuperAdminMode()) {
        elA.statusValue.textContent = "管理者（可檢視全部住民）";
      } else if (isCaregiverMode()) {
        elA.statusValue.textContent = "照護人員（僅檢視被指派的住民）";
      } else {
        elA.statusValue.textContent = "尚未登入";
      }
    }
    if (elA.logout) {
      elA.logout.classList.toggle("hidden", authState.authMode === "none");
    }
  }

  // CR-0042：依身分模式調整入口。caregiver 不顯示 super_admin-only 分頁。
  function applyAuthModeUi() {
    var caregiver = isCaregiverMode();
    [
      elU && elU.tabUsers,
      elP && elP.tabProducts,
      elO && elO.tabOrders,
      elCG && elCG.tab,
      elAS && elAS.tab,
    ].forEach(function (tab) {
      if (tab) tab.classList.toggle("hidden", caregiver);
    });
    // caregiver 模式若正停在 super_admin-only 分頁，切回照護提醒。
    if (caregiver) {
      var name = currentViewName();
      if (
        name === "users" ||
        name === "products" ||
        name === "orders" ||
        name === "caregivers" ||
        name === "assignments"
      ) {
        showView("alerts");
      }
    }
    updateAuthStatusUi();
    updateFirebasePanelUi();
  }

  // 目前顯示中的分頁名稱（含 super_admin-only 分頁，供 applyAuthModeUi 判斷）。
  function currentViewName() {
    if (elAN.view && !elAN.view.classList.contains("hidden")) return "analytics";
    if (elH.viewHealth && !elH.viewHealth.classList.contains("hidden")) return "health";
    if (elT.viewTasks && !elT.viewTasks.classList.contains("hidden")) return "tasks";
    if (elU.viewUsers && !elU.viewUsers.classList.contains("hidden")) return "users";
    if (elP.viewProducts && !elP.viewProducts.classList.contains("hidden")) return "products";
    if (elO.viewOrders && !elO.viewOrders.classList.contains("hidden")) return "orders";
    if (elCG.view && !elCG.view.classList.contains("hidden")) return "caregivers";
    if (elAS.view && !elAS.view.classList.contains("hidden")) return "assignments";
    return "alerts";
  }

  // 重新載入目前分頁資料（登入後刷新）。
  function reloadActiveView() {
    var name = currentViewName();
    if (name === "alerts") loadAlerts();
    else if (name === "health") {
      loadHealthOverview();
      loadElderList();
    } else if (name === "tasks") loadDailyTasks();
    else if (name === "users") loadUsers();
    else if (name === "products") loadProducts();
    else if (name === "orders") loadOrders();
    else if (name === "caregivers") loadCaregivers();
    else if (name === "assignments") loadAssignments();
    else loadAlerts();
  }

  function onLoginClick() {
    var mode = selectedAuthMode();
    if (mode === "none") {
      showAuthMessage("請先選擇身分（照護人員或管理者）。", true);
      return;
    }
    var token = elA.tokenInput ? (elA.tokenInput.value || "").trim() : "";
    if (!token) {
      showAuthMessage("請貼上登入權杖再登入。", true);
      return;
    }
    applyLogin(mode, token);
    if (elA.tokenInput) elA.tokenInput.value = "";
    // 不宣稱「已驗證」；實際由後端回應決定（401 → 重新登入）。
    showAuthMessage(
      mode === "caregiver"
        ? "正在以照護人員身分載入資料…"
        : "正在以管理者身分載入資料…",
      false
    );
    reloadActiveView();
  }

  function onLogoutClick() {
    logout();
    signOutFirebaseCaregiver();
    showAuthMessage("已登出。", false);
  }

  function firebaseConfig() {
    var cfg = (typeof window !== "undefined" && window.APP_CONFIG) || {};
    return cfg.firebase || cfg.firebaseConfig || null;
  }

  function hasFirebaseWebConfig() {
    var cfg = firebaseConfig();
    return !!(
      cfg &&
      typeof cfg === "object" &&
      cfg.apiKey &&
      cfg.authDomain &&
      cfg.projectId
    );
  }

  function setFirebaseStatus(text, isError) {
    if (!elA.firebaseStatus) return;
    elA.firebaseStatus.textContent = text || "";
    elA.firebaseStatus.classList.toggle("error", !!isError);
  }

  function setFirebaseButtonsDisabled(disabled) {
    [elA.firebaseEmailLogin, elA.firebaseGoogleLogin].forEach(function (btn) {
      if (btn) btn.disabled = !!disabled;
    });
  }

  function updateFirebasePanelUi() {
    if (!elA.firebasePanel) return;
    var caregiverSelected = selectedAuthMode() === "caregiver";
    elA.firebasePanel.classList.toggle("is-hidden", !caregiverSelected);
    if (!caregiverSelected) return;
    var configured = hasFirebaseWebConfig();
    elA.firebasePanel.classList.toggle("is-disabled", !configured);
    setFirebaseButtonsDisabled(!configured || firebaseAuthState.loading);
    if (!configured) {
      setFirebaseStatus("尚未設定 Firebase Web 登入，請暫用登入權杖備援。", false);
    } else if (!firebaseAuthState.ready && !firebaseAuthState.loading) {
      setFirebaseStatus("可使用 Email 或 Google 登入。", false);
    }
  }

  function firebaseErrorMessage(error) {
    var code = error && error.code ? String(error.code) : "";
    if (code === "auth/invalid-credential" || code === "auth/wrong-password") {
      return "Email 或密碼不太對，請再確認一次。";
    }
    if (code === "auth/user-not-found") {
      return "找不到這個照護人員帳號，請聯絡管理者確認。";
    }
    if (code === "auth/popup-closed-by-user") {
      return "登入視窗已關閉，尚未完成登入。";
    }
    if (code === "auth/unauthorized-domain") {
      return "這個後台網址尚未加入 Firebase 授權網域。";
    }
    if (code === "auth/network-request-failed") {
      return "網路不太穩，請稍後再試。";
    }
    return "登入沒有成功，請稍後再試。";
  }

  function applyFirebaseCaregiverLogin(user, token, options) {
    if (!token) {
      showAuthMessage("登入沒有成功，請稍後再試。", true);
      return;
    }
    if (elA.modeCaregiver) elA.modeCaregiver.checked = true;
    applyLogin("caregiver", token);
    firebaseAuthState.lastUid = user && user.uid ? user.uid : null;
    if (elA.tokenInput) elA.tokenInput.value = "";
    updateAuthHint();
    showAuthMessage("正在以照護人員身分載入資料…", false);
    if (!options || options.reload !== false) reloadActiveView();
  }

  async function ensureFirebaseAuth() {
    if (!hasFirebaseWebConfig()) {
      throw new Error("firebase_not_configured");
    }
    if (firebaseAuthState.ready && firebaseAuthState.auth) {
      return firebaseAuthState;
    }
    firebaseAuthState.loading = true;
    updateFirebasePanelUi();
    try {
      var appModule = await import(FIREBASE_APP_MODULE_URL);
      var authModule = await import(FIREBASE_AUTH_MODULE_URL);
      var apps =
        typeof appModule.getApps === "function" ? appModule.getApps() : [];
      var app = apps.length ? apps[0] : appModule.initializeApp(firebaseConfig());
      var auth = authModule.getAuth(app);
      if (authModule.setPersistence && authModule.browserLocalPersistence) {
        await authModule.setPersistence(auth, authModule.browserLocalPersistence);
      }
      firebaseAuthState.auth = auth;
      firebaseAuthState.modules = authModule;
      firebaseAuthState.ready = true;
      authModule.onAuthStateChanged(auth, function (user) {
        if (!user || isSuperAdminMode()) return;
        user
          .getIdToken()
          .then(function (token) {
            applyFirebaseCaregiverLogin(user, token, { reload: false });
          })
          .catch(function () {
            setFirebaseStatus("登入狀態已失效，請重新登入。", true);
          });
      });
      setFirebaseStatus("可使用 Email 或 Google 登入。", false);
      return firebaseAuthState;
    } catch (error) {
      setFirebaseStatus("Firebase 登入載入失敗，請暫用登入權杖備援。", true);
      throw error;
    } finally {
      firebaseAuthState.loading = false;
      updateFirebasePanelUi();
    }
  }

  async function onFirebaseEmailLoginClick() {
    var email = elA.firebaseEmail ? (elA.firebaseEmail.value || "").trim() : "";
    var password = elA.firebasePassword ? elA.firebasePassword.value || "" : "";
    if (!email || !password) {
      setFirebaseStatus("請輸入 Email 和密碼。", true);
      return;
    }
    try {
      setFirebaseButtonsDisabled(true);
      setFirebaseStatus("登入中…", false);
      var state = await ensureFirebaseAuth();
      var result = await state.modules.signInWithEmailAndPassword(
        state.auth,
        email,
        password
      );
      var token = await result.user.getIdToken();
      if (elA.firebasePassword) elA.firebasePassword.value = "";
      applyFirebaseCaregiverLogin(result.user, token);
      setFirebaseStatus("已登入。", false);
    } catch (error) {
      setFirebaseStatus(firebaseErrorMessage(error), true);
    } finally {
      setFirebaseButtonsDisabled(!hasFirebaseWebConfig());
    }
  }

  async function onFirebaseGoogleLoginClick() {
    try {
      setFirebaseButtonsDisabled(true);
      setFirebaseStatus("開啟 Google 登入中…", false);
      var state = await ensureFirebaseAuth();
      var provider = new state.modules.GoogleAuthProvider();
      var result = await state.modules.signInWithPopup(state.auth, provider);
      var token = await result.user.getIdToken();
      applyFirebaseCaregiverLogin(result.user, token);
      setFirebaseStatus("已登入。", false);
    } catch (error) {
      setFirebaseStatus(firebaseErrorMessage(error), true);
    } finally {
      setFirebaseButtonsDisabled(!hasFirebaseWebConfig());
    }
  }

  function signOutFirebaseCaregiver() {
    if (!firebaseAuthState.auth || !firebaseAuthState.modules) return;
    firebaseAuthState.modules.signOut(firebaseAuthState.auth).catch(function () {
      setFirebaseStatus("", false);
    });
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
    // 使用者管理為 super_admin-only：caregiver 顯示權限不足，不打 API。
    if (isCaregiverMode()) {
      setUsersStatus(FORBIDDEN_MSG, "error");
      return;
    }
    if (sessionInvalid) {
      setUsersStatus(SESSION_EXPIRED_MSG, "error");
      return;
    }
    if (!getAdminToken()) {
      setUsersStatus("請先在下方輸入管理者權杖（Admin Token），再重新整理。", "error");
      return;
    }
    setUsersStatus("使用者資料載入中...", "");
    fetch(adminUrl("/users"), { headers: adminAuthHeaders() })
      .then(function (res) {
        if (res.status === 401) {
          handleSessionExpired();
          throw new Error("session_expired");
        }
        if (res.status === 403) throw new Error("forbidden");
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
        if (err && err.message === "session_expired") {
          setUsersStatus(SESSION_EXPIRED_MSG, "error");
        } else if (err && err.message === "forbidden") {
          setUsersStatus(FORBIDDEN_MSG, "error");
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

  function dailyTaskVerificationClass(status) {
    if (status === "passed") return "ok";
    if (status === "failed") return "danger";
    return "review";
  }

  function dailyTaskReviewLabel(verification) {
    if (!verification) return "尚未送出照片";
    return verification.reviewRequired ? "需要照護者確認" : "暫不需人工確認";
  }

  function dailyTaskDetectedObjectsLabel(verification) {
    if (
      !verification ||
      !Array.isArray(verification.detectedObjects) ||
      verification.detectedObjects.length === 0
    ) {
      return "沒有可明確辨識的物件";
    }
    return verification.detectedObjects
      .slice(0, 5)
      .map(function (item) {
        return String(item || "").trim();
      })
      .filter(Boolean)
      .join("、") || "沒有可明確辨識的物件";
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
    var aiObjects = escapeHtml(dailyTaskDetectedObjectsLabel(v));
    var reviewLabel = escapeHtml(dailyTaskReviewLabel(v));
    var verificationClass = dailyTaskVerificationClass(
      v ? v.verificationStatus : "",
    );
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
      "</div>" +
      '<div class="task-verification-card task-verification-' +
      escapeHtml(verificationClass) +
      '">' +
      '<div class="task-verification-head">' +
      '<span class="task-verification-title">照片驗證摘要</span>' +
      '<span class="task-review-badge">' +
      reviewLabel +
      "</span>" +
      "</div>" +
      '<div class="task-verification-grid">' +
      "<span><b>AI 判斷</b>" +
      escapeHtml(aiStatus) +
      "</span>" +
      "<span><b>信心</b>" +
      escapeHtml(aiConfidence) +
      "</span>" +
      "<span><b>辨識內容</b>" +
      aiObjects +
      "</span>" +
      "<span><b>照片</b>" +
      proof +
      "</span>" +
      "</div>" +
      '<p class="task-verification-reason"><b>AI 原因：</b>' +
      aiReason +
      "</p>" +
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
  function clearDailyTaskStats() {
    ["statTotal", "statCompleted", "statPending", "statReview", "statMissed"].forEach(
      function (k) {
        if (elT[k]) elT[k].textContent = "—";
      }
    );
    if (elT.taskList) elT.taskList.innerHTML = "";
  }

  function loadDailyTasks() {
    if (
      !ensureCanFetch(function (msg) {
        clearDailyTaskStats();
        if (elT.tasksStatus) elT.tasksStatus.textContent = msg;
      })
    ) {
      return;
    }
    var filter = elT.tasksFilter ? elT.tasksFilter.value : "";
    var url = adminUrl("/daily-care-tasks");
    if (filter) url += "?status=" + encodeURIComponent(filter);
    if (elT.tasksStatus) elT.tasksStatus.textContent = "載入中…";

    fetch(url, { headers: authHeaders() })
      .then(function (r) {
        if (r.status === 401) {
          handleSessionExpired();
          throw new Error("session_expired");
        }
        if (r.status === 403) throw new Error("forbidden");
        if (!r.ok) throw new Error("HTTP " + r.status);
        return r.json();
      })
      .then(function (data) {
        var tasks = data && Array.isArray(data.tasks) ? data.tasks : [];
        renderDailyTasks(tasks);
        if (elT.tasksStatus) {
          // caregiver 無授權住民 → 空清單，顯示友善空狀態。
          elT.tasksStatus.textContent =
            tasks.length === 0 && isCaregiverMode() ? EMPTY_CAREGIVER_MSG : "";
        }
      })
      .catch(function (err) {
        clearDailyTaskStats();
        if (elT.tasksStatus) {
          if (err && err.message === "session_expired") {
            elT.tasksStatus.textContent = SESSION_EXPIRED_MSG;
          } else if (err && err.message === "forbidden") {
            elT.tasksStatus.textContent = FORBIDDEN_MSG;
          } else {
            elT.tasksStatus.textContent = "目前連不到後端，待會再重新整理看看。";
          }
        }
      });
  }

  function clearHealthOverview() {
    ["ovTotal", "ovActive", "ovAlerts", "ovHighrisk", "ovEmotion", "ovCognitive"].forEach(
      function (k) {
        elH[k].textContent = "—";
      }
    );
  }

  // GET /api/admin/overview → 六指標。此端點為 super_admin-only，
  // caregiver 模式不打 API（避免一直 403 洗版），整體概況留「—」。
  function loadHealthOverview() {
    if (isCaregiverMode()) {
      clearHealthOverview();
      return;
    }
    if (sessionInvalid || !getAdminToken()) {
      clearHealthOverview();
      return;
    }
    fetch(adminUrl("/overview"), { headers: adminAuthHeaders() })
      .then(function (r) {
        if (r.status === 401) {
          handleSessionExpired();
          throw new Error("session_expired");
        }
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
        clearHealthOverview();
      });
  }

  // GET /api/admin/elders → 長者列表（caregiver-capable，後端依授權住民過濾）。
  function loadElderList() {
    if (
      !ensureCanFetch(function (msg) {
        elH.elderListStatus.textContent = msg;
        elH.elderList.innerHTML = "";
      })
    ) {
      return;
    }
    elH.elderListStatus.textContent = "載入中…";
    fetch(adminUrl("/elders"), { headers: authHeaders() })
      .then(function (r) {
        if (r.status === 401) {
          handleSessionExpired();
          throw new Error("session_expired");
        }
        if (r.status === 403) throw new Error("forbidden");
        if (!r.ok) throw new Error("HTTP " + r.status);
        return r.json();
      })
      .then(function (rows) {
        if (!Array.isArray(rows) || rows.length === 0) {
          // caregiver 無授權住民 → 空陣列 → 友善空狀態。
          elH.elderListStatus.textContent = isCaregiverMode()
            ? EMPTY_CAREGIVER_MSG
            : "目前沒有長者資料。";
          elH.elderList.innerHTML = "";
          return;
        }
        elH.elderListStatus.textContent = "";
        renderElderList(rows);
      })
      .catch(function (err) {
        elH.elderList.innerHTML = "";
        if (err && err.message === "session_expired") {
          elH.elderListStatus.textContent = SESSION_EXPIRED_MSG;
        } else if (err && err.message === "forbidden") {
          elH.elderListStatus.textContent = FORBIDDEN_MSG;
        } else {
          elH.elderListStatus.textContent =
            "暫時連不上後端，請確認服務已啟動後再重新整理。";
        }
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
    if (sessionInvalid || !hasActiveToken()) {
      elH.healthStatus.textContent = sessionInvalid
        ? SESSION_EXPIRED_MSG
        : NEED_LOGIN_MSG;
      return;
    }
    elH.healthStatus.textContent = "載入中…";
    fetch(adminUrl("/elders/" + encodeURIComponent(elderId)), {
      headers: authHeaders(),
    })
      .then(function (r) {
        if (r.status === 401) {
          handleSessionExpired();
          throw new Error("session_expired");
        }
        if (r.status === 403) throw new Error("forbidden");
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
      .catch(function (err) {
        if (err && err.message === "session_expired") {
          elH.healthStatus.textContent = SESSION_EXPIRED_MSG;
        } else if (err && err.message === "forbidden") {
          // 跨住民 / 無權限：權限不足，不清 token。
          elH.healthStatus.textContent = FORBIDDEN_MSG;
        } else {
          elH.healthStatus.textContent =
            "暫時讀不到這位長者的健康分析，請稍後再試。";
        }
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

  // ========== 長者狀態分析 Dashboard（CR-0086）==========
  // 長者選擇器沿用 GET /api/admin/elders（caregiver-capable，後端依授權住民過濾）；
  // 分析資料用 GET /api/caregiver/analytics（同授權模型）。誠實呈現空狀態，不捏造。

  function analyticsUrl(elderId, rangeDays) {
    return (
      getApiBase() +
      "/caregiver/analytics?elderId=" +
      encodeURIComponent(elderId) +
      "&rangeDays=" +
      encodeURIComponent(rangeDays)
    );
  }

  // 載入長者選擇器（授權住民）。
  function loadAnalyticsElders() {
    if (
      !ensureCanFetch(function (msg) {
        elAN.status.textContent = msg;
        elAN.elderSelect.innerHTML = "";
      })
    ) {
      return;
    }
    elAN.status.textContent = "載入中…";
    fetch(adminUrl("/elders"), { headers: authHeaders() })
      .then(function (r) {
        if (r.status === 401) {
          handleSessionExpired();
          throw new Error("session_expired");
        }
        if (r.status === 403) throw new Error("forbidden");
        if (!r.ok) throw new Error("HTTP " + r.status);
        return r.json();
      })
      .then(function (rows) {
        if (!Array.isArray(rows) || rows.length === 0) {
          elAN.elderSelect.innerHTML = "";
          elAN.status.textContent = isCaregiverMode()
            ? EMPTY_CAREGIVER_MSG
            : "目前沒有長者資料。";
          elAN.body.classList.add("hidden");
          return;
        }
        elAN.elderSelect.innerHTML =
          '<option value="">請選擇長者</option>' +
          rows
            .map(function (e) {
              return (
                '<option value="' +
                escapeHtml(e.elderId) +
                '">' +
                escapeHtml(e.displayName || e.elderId) +
                "</option>"
              );
            })
            .join("");
        // 只有一位授權長者時自動選取並載入。
        if (rows.length === 1) {
          elAN.elderSelect.value = rows[0].elderId;
          analyticsElderId = rows[0].elderId;
          loadResidentAnalytics();
        } else {
          elAN.status.textContent = "請從上方選擇一位長者，查看近期狀態分析。";
        }
      })
      .catch(function (err) {
        elAN.elderSelect.innerHTML = "";
        elAN.body.classList.add("hidden");
        if (err && err.message === "session_expired") {
          elAN.status.textContent = SESSION_EXPIRED_MSG;
        } else if (err && err.message === "forbidden") {
          elAN.status.textContent = FORBIDDEN_MSG;
        } else {
          elAN.status.textContent =
            "暫時連不上後端，請確認服務已啟動後再重新整理。";
        }
      });
  }

  // 載入並渲染選定長者的分析資料。
  function loadResidentAnalytics() {
    var elderId = analyticsElderId;
    if (!elderId) {
      elAN.body.classList.add("hidden");
      elAN.status.textContent = "請從上方選擇一位長者，查看近期狀態分析。";
      return;
    }
    if (sessionInvalid || !hasActiveToken()) {
      elAN.status.textContent = sessionInvalid ? SESSION_EXPIRED_MSG : NEED_LOGIN_MSG;
      return;
    }
    var rangeDays = elAN.rangeSelect ? elAN.rangeSelect.value : 7;
    elAN.body.classList.add("hidden");
    elAN.status.textContent = "載入中…";
    fetch(analyticsUrl(elderId, rangeDays), { headers: authHeaders() })
      .then(function (r) {
        if (r.status === 401) {
          handleSessionExpired();
          throw new Error("session_expired");
        }
        if (r.status === 403) throw new Error("forbidden");
        if (!r.ok) throw new Error("HTTP " + r.status);
        return r.json();
      })
      .then(function (data) {
        elAN.status.textContent = "";
        renderAnalytics(data || {});
        elAN.body.classList.remove("hidden");
      })
      .catch(function (err) {
        elAN.body.classList.add("hidden");
        if (err && err.message === "session_expired") {
          elAN.status.textContent = SESSION_EXPIRED_MSG;
        } else if (err && err.message === "forbidden") {
          elAN.status.textContent = FORBIDDEN_MSG;
        } else {
          elAN.status.textContent =
            "暫時讀不到這位長者的狀態分析，請稍後再試。";
        }
      });
  }

  function pct(ratio) {
    if (ratio == null) return "—";
    return Math.round(Number(ratio) * 100) + "%";
  }

  function statTile(value, label, cls) {
    return (
      '<div class="stat-card' +
      (cls ? " " + cls : "") +
      '"><div class="stat-text"><div class="stat-value">' +
      escapeHtml(value == null ? "—" : String(value)) +
      '</div><div class="stat-label">' +
      escapeHtml(label) +
      "</div></div></div>"
    );
  }

  function renderAnalytics(data) {
    var s = data.summary || {};
    var ca = data.careAlertStats || {};
    var ts = data.taskStats || {};
    var us = data.usageStats || {};
    var game = data.gameMetrics || {};
    var pet = data.petStatus || {};
    var emotion = Array.isArray(data.emotionTrend) ? data.emotionTrend : [];

    var html = "";

    // 1) 今日總覽
    html += '<section class="panel"><h3 class="analysis-title">今日總覽</h3>';
    html += '<div class="stats stat-grid">';
    html += statTile(s.todayAlertCount, "今日警示數", "stat-high");
    html += statTile(s.rangeAlertCount, "區間警示數");
    html +=
      statTile(
        s.taskCompletionRate == null ? "—" : pct(s.taskCompletionRate),
        "任務完成率",
      );
    html += statTile(s.latestEmotion || "—", "最近情緒");
    html +=
      '<div class="stat-card"><div class="stat-text"><div class="stat-value">' +
      (s.latestRiskLevel ? riskBadge(s.latestRiskLevel) : "—") +
      '</div><div class="stat-label">最近風險等級</div></div></div>';
    html += statTile(formatTime(s.lastInteractionAt), "最近互動時間");
    html += "</div></section>";

    // 2) Care Alert 統計
    html += '<section class="panel"><h3 class="analysis-title">Care Alert 統計</h3>';
    if (!ca.total) {
      html += '<p class="empty">近期沒有警示紀錄。</p>';
    } else {
      html += '<div class="stats stat-grid">';
      html += statTile(ca.low, "一般 low");
      html += statTile(ca.medium, "持續觀察 medium");
      html += statTile(ca.high, "需通知 high", "stat-high");
      html += statTile(ca.urgent, "緊急 urgent", "stat-urgent");
      html += "</div>";
      html += '<div class="metric-grid">';
      html += metricCard("總警示數", String(ca.total), null);
      html += metricCard("高風險比例", pct(ca.highRiskRatio), "(high + urgent) / 總數");
      html += metricCard("最近一次警示", formatTime(ca.lastAlertAt), null);
      html += "</div>";
    }
    html += "</section>";

    // 3) 任務 / 簽到
    html += '<section class="panel"><h3 class="analysis-title">任務與簽到狀況</h3>';
    if (!ts.total) {
      html += '<p class="empty">這位長者目前沒有日常任務紀錄。</p>';
    } else {
      var byType = ts.byType || {};
      var typeLabels = { medication: "吃藥", hydration: "喝水", exercise: "運動" };
      ["medication", "hydration", "exercise"].forEach(function (t) {
        var b = byType[t] || { completed: 0, total: 0 };
        var ratio = b.total ? b.completed / b.total : 0;
        html += barRow(
          typeLabels[t] + " " + b.completed + "/" + b.total,
          ratio,
        );
      });
      html += '<div class="metric-grid">';
      html += metricCard("整體完成率", pct(ts.completionRate), ts.completed + "/" + ts.total);
      html += metricCard("未完成任務", String(ts.pending), null);
      html += metricCard(
        "簽到狀態",
        ts.checkInStatus === "completed"
          ? "今日已簽到"
          : ts.checkInStatus === "pending"
            ? "今日尚未簽到"
            : "—",
        ts.lastCheckInAt ? "最近：" + formatTime(ts.lastCheckInAt) : null,
      );
      html += "</div>";
    }
    html += "</section>";

    // 4) App 使用狀況（來自 app_usage_events 真實上報）
    html += '<section class="panel"><h3 class="analysis-title">App 使用狀況</h3>';
    if (!us.available) {
      html += '<p class="muted data-insufficient">目前尚無 App 使用上報資料。</p>';
    } else {
      html += '<div class="metric-grid">';
      html += metricCard("使用天數", String(us.activeDays || 0), "區間內");
      html += metricCard("語音互動", String(us.voiceInteractions || 0), null);
      html += metricCard("語音導覽", String(us.voiceNavigations || 0), null);
      html += metricCard("打字訊息", String(us.typedChats || 0), null);
      html += metricCard("寵物互動", String(us.petInteractions || 0), null);
      html += metricCard("建立提醒", String(us.remindersCreated || 0), null);
      html += metricCard("任務完成", String(us.dailyTasksCompleted || 0), null);
      html += metricCard("拼圖完成", String(us.puzzleCompletions || 0), null);
      html += metricCard("設定調整", String(us.settingsChanges || 0), null);
      html += metricCard("最近使用", formatTime(us.lastEventAt), null);
      html += "</div>";
    }
    html += "</section>";

    // 5) 情緒趨勢（誠實標註；無真實資料 → 資料不足）
    html += '<section class="panel"><h3 class="analysis-title">情緒趨勢</h3>';
    html += dataSourceBadge(data.emotionDataSource);
    if (isInsufficient(data.emotionDataSource, emotion)) {
      html += insufficientBlock("情緒辨識");
    } else {
      html += '<div class="emotion-trend">';
      html += emotion
        .map(function (e) {
          return (
            '<div class="bar-row"><span class="bar-label">' +
            escapeHtml(formatTime(e.date)) +
            "・" +
            escapeHtml(e.emotion || "—") +
            "</span></div>"
          );
        })
        .join("");
      html += "</div>";
    }
    html += "</section>";

    // 6) 遊戲退化指標
    html += '<section class="panel"><h3 class="analysis-title">遊戲認知退化指標</h3>';
    html += dataSourceBadge(game.dataSource);
    if (!game.hasEnoughData) {
      html +=
        '<p class="muted data-insufficient">' +
        escapeHtml(game.message || "目前尚無足夠遊戲紀錄") +
        "。</p>";
    } else {
      html += '<div class="metric-grid">';
      html += metricCard("近期趨勢", game.trend === "declining" ? "變慢（需關注）" : "穩定", null);
      html += "</div>";
    }
    html += "</section>";

    // 7) 寵物照護狀態（來自 app_usage_events）
    html += '<section class="panel"><h3 class="analysis-title">寵物照護狀態</h3>';
    if (!pet.available) {
      html +=
        '<p class="muted data-insufficient">' +
        escapeHtml(pet.message || "目前尚無寵物互動上報資料") +
        "。</p>";
    } else {
      html += '<div class="metric-grid">';
      html += metricCard("寵物類型", petTypeLabel(pet.selectedPetType || pet.petType), null);
      html += metricCard("視覺風格", petVisualStyleLabel(pet.visualStyle), null);
      html += metricCard("成長階段", petGrowthStageLabel(pet.growthStage), null);
      html += metricCard("心情", pet.mood || "—", null);
      html += metricCard("飽足度", pet.satiety == null ? "—" : String(pet.satiety), null);
      html += metricCard("親密度", pet.intimacy == null ? "—" : String(pet.intimacy), null);
      html += metricCard("互動次數", String(pet.interactionCount || 0), null);
      html += metricCard("最近互動", formatTime(pet.lastInteractionAt), null);
      html += "</div>";
    }
    html += "</section>";

    elAN.body.innerHTML = html;
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
    // CR-0065：marketplace 在正式版停用（後端回 501）。功能關閉時一律不打後端，
    // 避免管理者載入時噴 501 與卡住流程；分頁入口本就已由 applyFeatureFlags 隱藏。
    if (!featureEnabled("marketplace")) {
      setProductsStatus("商品商城功能尚未開放。", "");
      return;
    }
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
    // 訂單管理為 super_admin-only：caregiver 顯示權限不足，不打 API。
    if (isCaregiverMode()) {
      setOrdersStatus(FORBIDDEN_MSG, "error");
      if (elO.list) elO.list.innerHTML = "";
      if (elO.count) elO.count.textContent = "";
      return;
    }
    if (sessionInvalid) {
      setOrdersStatus(SESSION_EXPIRED_MSG, "error");
      return;
    }
    if (!getAdminToken()) {
      setOrdersStatus("請先輸入管理者權杖（Admin Token），再重新整理。", "error");
      if (elO.list) elO.list.innerHTML = "";
      if (elO.count) elO.count.textContent = "";
      return;
    }
    // CR-0065：marketplace 在正式版停用（後端回 501）。功能關閉時不打後端，
    // 避免管理者載入時噴 501 與卡住流程；分頁入口本就已由 applyFeatureFlags 隱藏。
    if (!featureEnabled("marketplace")) {
      setOrdersStatus("訂單管理功能尚未開放。", "");
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
      '<div class="form-actions"><button type="button" id="order-save" class="btn btn-primary">儲存更新</button>' +
      '<button type="button" id="order-delete" class="btn btn-danger">刪除訂單</button></div>';

    var saveBtn = document.getElementById("order-save");
    if (saveBtn) {
      saveBtn.addEventListener("click", function () {
        updateOrderFromDetail(order.id);
      });
    }
    var deleteBtn = document.getElementById("order-delete");
    if (deleteBtn) {
      deleteBtn.addEventListener("click", function () {
        deleteOrderFromDetail(order.id);
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

  function deleteOrderFromDetail(id) {
    var statusMsg = document.getElementById("order-detail-status");
    if (!getAdminToken()) {
      if (statusMsg) {
        statusMsg.textContent = "請先輸入管理者權杖。";
        statusMsg.classList.add("error");
      }
      return;
    }
    if (
      !window.confirm(
        "確定要刪除這筆訂單嗎？刪除後無法復原，商品庫存會自動加回。",
      )
    ) {
      return;
    }
    if (statusMsg) {
      statusMsg.textContent = "刪除中…";
      statusMsg.classList.remove("error");
    }
    fetch(adminUrl("/marketplace/orders/" + encodeURIComponent(id)), {
      method: "DELETE",
      headers: adminJsonHeaders(),
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
              : "刪除沒成功，請稍後再試。";
          statusMsg.classList.add("error");
        }
      });
  }

  // ===================================================================
  // CR-0044 照護人員 / 住民授權指派管理（super_admin-only provisioning）
  // -------------------------------------------------------------------
  // 全部走 super_admin token（adminAuthHeaders / adminJsonHeaders），
  // 端點 GET/POST/PATCH/DELETE /api/admin/caregivers 與
  // /api/admin/resident-caregiver-links（CR-0043 後端契約，本案不改後端）。
  // caregiver 模式不顯示入口、且絕不發送這些 management API request。
  // ===================================================================

  // 後端回應 { ok:false, error } → 友善白話訊息（不顯示原始錯誤碼 / stack）。
  function provisioningErrorMessage(error, map) {
    if (error && map && map[error]) return map[error];
    return "操作沒有成功，請稍後再試。";
  }

  var CAREGIVER_ERROR_MSG = {
    email_required: "請填寫 Email。",
    email_exists: "這個 Email 已經有人使用了，請換一個。",
    firebase_uid_exists:
      "這個 Firebase UID 已經綁到其他帳號。請先編輯既有照護人員，或確認該 UID 沒有被住民帳號使用。",
    failed_to_create_caregiver:
      "新增照護人員沒有成功。請確認 Email 與 Firebase UID 沒有被其他帳號使用。",
    failed_to_update_caregiver:
      "更新照護人員沒有成功。請確認 Firebase UID 沒有被其他帳號使用。",
    failed_to_load_caregivers:
      "照護人員資料載入失敗。請確認正式後端資料庫已完成 migration。",
    database_schema_not_ready:
      "正式後端資料庫尚未完成 migration。請對目前 Render 後端使用的 DATABASE_URL 執行 db:migrate 後再試。",
    invalid_payload: "沒有要更新的內容。",
    invalid_status: "狀態設定不正確。",
    not_found: "找不到這位照護人員，請重新整理後再試。",
  };
  var LINK_ERROR_MSG = {
    invalid_payload: "請選擇住民與照護人員。",
    invalid_role: "授權角色設定不正確。",
    resident_not_found: "找不到這位住民，請重新整理後再試。",
    caregiver_not_found: "找不到這位照護人員，請重新整理後再試。",
    link_exists: "這位照護人員已經有這位住民的有效授權了。",
    not_found: "找不到這筆授權，請重新整理後再試。",
  };

  // ---- 照護人員管理 ----

  function setCaregiversStatus(msg, kind) {
    if (!elCG.status) return;
    elCG.status.textContent = msg || "";
    elCG.status.classList.toggle("error", kind === "error");
  }

  function caregiverFirebaseLabel(uid) {
    return uid ? "已綁定" : "待綁定";
  }

  function caregiverStatusBadge(status) {
    var on = status === "active";
    return (
      '<span class="badge status ' +
      (on ? "status-resolved" : "status-off") +
      '">' +
      (on ? "啟用中" : "已停用") +
      "</span>"
    );
  }

  // GET /api/admin/caregivers（super_admin-only）。caregiver 模式不打 API。
  function loadCaregivers() {
    if (elCG.tableWrap) elCG.tableWrap.innerHTML = "";
    if (elCG.count) elCG.count.textContent = "";
    if (isCaregiverMode()) {
      setCaregiversStatus(FORBIDDEN_MSG, "error");
      return;
    }
    if (sessionInvalid) {
      setCaregiversStatus(SESSION_EXPIRED_MSG, "error");
      return;
    }
    if (!getAdminToken()) {
      setCaregiversStatus(NEED_ADMIN_MSG, "error");
      return;
    }
    setCaregiversStatus("照護人員載入中…", "");
    fetch(adminUrl("/caregivers"), { headers: adminAuthHeaders() })
      .then(function (r) {
        if (r.status === 401) {
          handleSessionExpired();
          throw new Error("session_expired");
        }
        if (r.status === 403) throw new Error("forbidden");
        return r.json().then(function (body) {
          if (!r.ok) {
            throw new Error(
              "api:" + (body && body.error ? body.error : "unknown")
            );
          }
          return body;
        });
      })
      .then(function (body) {
        if (!body || body.ok !== true || !Array.isArray(body.caregivers)) {
          throw new Error("bad_payload");
        }
        caregiversCache = body.caregivers;
        renderCaregivers(body.caregivers);
      })
      .catch(function (err) {
        if (elCG.tableWrap) elCG.tableWrap.innerHTML = "";
        if (elCG.count) elCG.count.textContent = "";
        if (err && err.message === "session_expired") {
          setCaregiversStatus(SESSION_EXPIRED_MSG, "error");
        } else if (err && err.message === "forbidden") {
          setCaregiversStatus(FORBIDDEN_MSG, "error");
        } else if (err && err.message && err.message.indexOf("api:") === 0) {
          setCaregiversStatus(
            provisioningErrorMessage(err.message.slice(4), CAREGIVER_ERROR_MSG),
            "error"
          );
        } else {
          setCaregiversStatus("目前連不到後端，待會再重新整理看看。", "error");
        }
      });
  }

  function renderCaregivers(list) {
    if (elCG.count) {
      elCG.count.textContent = list.length ? "共 " + list.length + " 位" : "";
    }
    if (!list.length) {
      setCaregiversStatus(EMPTY_CAREGIVERS_MSG, "");
      elCG.tableWrap.innerHTML = "";
      return;
    }
    setCaregiversStatus("", "");
    var rows = list
      .map(function (c) {
        var active = c.status === "active";
        return (
          "<tr>" +
          "<td>" + escapeHtml(c.displayName || "—") + "</td>" +
          "<td>" + escapeHtml(c.emailMasked || "—") + "</td>" +
          "<td>" + escapeHtml(caregiverFirebaseLabel(c.firebaseUid)) + "</td>" +
          "<td>" + caregiverStatusBadge(c.status) + "</td>" +
          "<td>" + escapeHtml(formatTime(c.createdAt)) + "</td>" +
          "<td>" + escapeHtml(c.updatedAt ? formatTime(c.updatedAt) : "—") + "</td>" +
          '<td class="row-actions">' +
          '<button class="btn btn-sm" data-action="edit" data-id="' +
          escapeHtml(c.id) +
          '">編輯</button>' +
          '<button class="btn btn-sm" data-action="toggle" data-id="' +
          escapeHtml(c.id) +
          '" data-status="' +
          escapeHtml(c.status) +
          '">' +
          (active ? "停用" : "啟用") +
          "</button>" +
          "</td>" +
          "</tr>"
        );
      })
      .join("");
    elCG.tableWrap.innerHTML =
      '<table class="users-table"><thead><tr>' +
      "<th>顯示名稱</th><th>Email</th><th>Firebase 綁定</th><th>狀態</th><th>建立時間</th><th>更新時間</th><th>操作</th>" +
      "</tr></thead><tbody>" +
      rows +
      "</tbody></table>";
    var btns = elCG.tableWrap.querySelectorAll("button[data-action]");
    for (var i = 0; i < btns.length; i++) {
      btns[i].addEventListener("click", onCaregiverAction);
    }
  }

  function onCaregiverAction(e) {
    var btn = e.currentTarget;
    var id = btn.getAttribute("data-id");
    var action = btn.getAttribute("data-action");
    if (action === "edit") {
      var found = null;
      for (var i = 0; i < caregiversCache.length; i++) {
        if (caregiversCache[i].id === id) {
          found = caregiversCache[i];
          break;
        }
      }
      openCaregiverForm(found);
    } else if (action === "toggle") {
      toggleCaregiverStatus(id, btn.getAttribute("data-status"));
    }
  }

  function caregiverFormError(msg) {
    if (!elCG.formStatus) return;
    elCG.formStatus.textContent = msg || "";
    elCG.formStatus.classList.toggle("error", !!msg);
  }

  // caregiver 為 null → 新增；否則編輯（email 後端只回遮蔽值，編輯時留空＝不變更）。
  function openCaregiverForm(caregiver) {
    if (elCG.form) elCG.form.reset();
    caregiverFormError("");
    if (caregiver) {
      elCG.formTitle.textContent = "編輯照護人員";
      elCG.fId.value = caregiver.id || "";
      elCG.fName.value = caregiver.displayName || "";
      elCG.fEmail.value = "";
      if (elCG.fEmailHint) {
        elCG.fEmailHint.textContent =
          "目前 Email：" +
          (caregiver.emailMasked || "—") +
          "。留空表示不變更；要更換才填新的 Email。";
      }
      elCG.fFirebase.value = caregiver.firebaseUid || "";
    } else {
      elCG.formTitle.textContent = "新增照護人員";
      elCG.fId.value = "";
      if (elCG.fEmailHint) {
        elCG.fEmailHint.textContent = "照護人員的登入 Email，需全系統唯一。";
      }
    }
    if (elCG.overlay) elCG.overlay.classList.remove("hidden");
  }

  function closeCaregiverForm() {
    if (elCG.overlay) elCG.overlay.classList.add("hidden");
  }

  function submitCaregiverForm(e) {
    if (e) e.preventDefault();
    if (isCaregiverMode() || !getAdminToken()) {
      caregiverFormError(NEED_ADMIN_MSG);
      return;
    }
    var id = (elCG.fId.value || "").trim();
    var name = (elCG.fName.value || "").trim();
    var email = (elCG.fEmail.value || "").trim();
    var firebaseUid = (elCG.fFirebase.value || "").trim();
    if (!name) {
      caregiverFormError("請填寫顯示名稱。");
      return;
    }
    var payload;
    var url;
    var method;
    if (id) {
      // 編輯：displayName / firebaseUid 一律送；email 留空＝不變更。
      payload = { displayName: name, firebaseUid: firebaseUid };
      if (email) payload.email = email;
      url = adminUrl("/caregivers/" + encodeURIComponent(id));
      method = "PATCH";
    } else {
      // 新增：email 必填。
      if (!email) {
        caregiverFormError("請填寫 Email。");
        return;
      }
      payload = { email: email, displayName: name };
      if (firebaseUid) payload.firebaseUid = firebaseUid;
      url = adminUrl("/caregivers");
      method = "POST";
    }
    caregiverFormError("");
    if (elCG.formStatus) elCG.formStatus.textContent = "儲存中…";
    fetch(url, {
      method: method,
      headers: adminJsonHeaders(),
      body: JSON.stringify(payload),
    })
      .then(function (r) {
        if (r.status === 401) {
          handleSessionExpired();
          throw new Error("session_expired");
        }
        if (r.status === 403) throw new Error("forbidden");
        return r.json().then(function (body) {
          if (!r.ok || !body || body.ok !== true) {
            throw new Error(
              "api:" + (body && body.error ? body.error : "unknown")
            );
          }
          return body;
        });
      })
      .then(function () {
        closeCaregiverForm();
        loadCaregivers(); // 建立 / 編輯成功後刷新列表。
      })
      .catch(function (err) {
        var msg = err && err.message ? err.message : "";
        if (msg === "session_expired") {
          caregiverFormError(SESSION_EXPIRED_MSG);
        } else if (msg === "forbidden") {
          caregiverFormError(FORBIDDEN_MSG);
        } else if (msg.indexOf("api:") === 0) {
          caregiverFormError(
            provisioningErrorMessage(msg.slice(4), CAREGIVER_ERROR_MSG)
          );
        } else {
          caregiverFormError("儲存沒有成功，請稍後再試。");
        }
      });
  }

  function toggleCaregiverStatus(id, currentStatus) {
    if (!id) return;
    if (isCaregiverMode() || !getAdminToken()) {
      setCaregiversStatus(NEED_ADMIN_MSG, "error");
      return;
    }
    var next = currentStatus === "active" ? "inactive" : "active";
    if (next === "inactive") {
      // 停用提示（白話說明影響）。
      if (
        !window.confirm(
          "停用後，該照護人員將無法查看被指派住民資料。\n確定要停用嗎？"
        )
      ) {
        return;
      }
    }
    setCaregiversStatus("更新中…", "");
    fetch(adminUrl("/caregivers/" + encodeURIComponent(id) + "/status"), {
      method: "PATCH",
      headers: adminJsonHeaders(),
      body: JSON.stringify({ status: next }),
    })
      .then(function (r) {
        if (r.status === 401) {
          handleSessionExpired();
          throw new Error("session_expired");
        }
        if (r.status === 403) throw new Error("forbidden");
        if (!r.ok) throw new Error("HTTP " + r.status);
        return r.json();
      })
      .then(function () {
        loadCaregivers();
        setCaregiversStatus(
          next === "active" ? "已啟用此照護人員。" : "已停用此照護人員。",
          ""
        );
      })
      .catch(function (err) {
        if (err && err.message === "session_expired") {
          setCaregiversStatus(SESSION_EXPIRED_MSG, "error");
        } else if (err && err.message === "forbidden") {
          setCaregiversStatus(FORBIDDEN_MSG, "error");
        } else {
          setCaregiversStatus("狀態更新沒有成功，請稍後再試。", "error");
        }
      });
  }

  // ---- 住民授權指派 ----

  function setAssignmentsStatus(msg, kind) {
    if (!elAS.status) return;
    elAS.status.textContent = msg || "";
    elAS.status.classList.toggle("error", kind === "error");
  }

  function roleLabel(role) {
    return ROLE_LABELS[role] || role || "—";
  }

  function linkStatusBadge(status) {
    var on = status === "active";
    return (
      '<span class="badge status ' +
      (on ? "status-resolved" : "status-off") +
      '">' +
      (on ? "生效中" : "已停用") +
      "</span>"
    );
  }

  // GET /api/admin/resident-caregiver-links（super_admin-only）。caregiver 模式不打 API。
  function loadAssignments() {
    if (elAS.tableWrap) elAS.tableWrap.innerHTML = "";
    if (elAS.count) elAS.count.textContent = "";
    if (isCaregiverMode()) {
      setAssignmentsStatus(FORBIDDEN_MSG, "error");
      return;
    }
    if (sessionInvalid) {
      setAssignmentsStatus(SESSION_EXPIRED_MSG, "error");
      return;
    }
    if (!getAdminToken()) {
      setAssignmentsStatus(NEED_ADMIN_MSG, "error");
      return;
    }
    setAssignmentsStatus("授權指派載入中…", "");
    fetch(adminUrl("/resident-caregiver-links"), { headers: adminAuthHeaders() })
      .then(function (r) {
        if (r.status === 401) {
          handleSessionExpired();
          throw new Error("session_expired");
        }
        if (r.status === 403) throw new Error("forbidden");
        if (!r.ok) throw new Error("HTTP " + r.status);
        return r.json();
      })
      .then(function (body) {
        if (!body || body.ok !== true || !Array.isArray(body.links)) {
          throw new Error("bad_payload");
        }
        renderAssignments(body.links);
      })
      .catch(function (err) {
        if (elAS.tableWrap) elAS.tableWrap.innerHTML = "";
        if (elAS.count) elAS.count.textContent = "";
        if (err && err.message === "session_expired") {
          setAssignmentsStatus(SESSION_EXPIRED_MSG, "error");
        } else if (err && err.message === "forbidden") {
          setAssignmentsStatus(FORBIDDEN_MSG, "error");
        } else {
          setAssignmentsStatus("目前連不到後端，待會再重新整理看看。", "error");
        }
      });
  }

  function renderAssignments(list) {
    if (elAS.count) {
      elAS.count.textContent = list.length ? "共 " + list.length + " 筆" : "";
    }
    if (!list.length) {
      setAssignmentsStatus(EMPTY_ASSIGNMENTS_MSG, "");
      elAS.tableWrap.innerHTML = "";
      return;
    }
    setAssignmentsStatus("", "");
    var rows = list
      .map(function (l) {
        var active = l.status === "active";
        var actions =
          '<button class="btn btn-sm" data-action="role" data-id="' +
          escapeHtml(l.id) +
          '" data-role="' +
          escapeHtml(l.role || "primary") +
          '"' +
          (active ? "" : " disabled") +
          ">改角色</button>";
        if (active) {
          actions +=
            '<button class="btn btn-sm" data-action="disable" data-id="' +
            escapeHtml(l.id) +
            '">停用</button>';
        } else {
          // 後端無「重新啟用既有關聯」端點；重新啟用＝以相同住民+人員+角色另建一筆 active 關聯。
          actions +=
            '<button class="btn btn-sm" data-action="enable"' +
            ' data-resident="' +
            escapeHtml(l.residentId || "") +
            '" data-caregiver="' +
            escapeHtml(l.caregiverId || "") +
            '" data-role="' +
            escapeHtml(l.role || "primary") +
            '">重新啟用</button>';
        }
        return (
          "<tr>" +
          "<td>" + escapeHtml(l.residentName || l.residentId || "—") + "</td>" +
          "<td>" + escapeHtml(l.caregiverName || l.caregiverId || "—") + "</td>" +
          "<td>" + escapeHtml(roleLabel(l.role)) + "</td>" +
          "<td>" + linkStatusBadge(l.status) + "</td>" +
          "<td>" + escapeHtml(formatTime(l.createdAt)) + "</td>" +
          "<td>" + escapeHtml(l.updatedAt ? formatTime(l.updatedAt) : "—") + "</td>" +
          '<td class="row-actions">' +
          actions +
          "</td>" +
          "</tr>"
        );
      })
      .join("");
    elAS.tableWrap.innerHTML =
      '<table class="users-table"><thead><tr>' +
      "<th>住民</th><th>照護人員</th><th>角色</th><th>狀態</th><th>建立時間</th><th>更新時間</th><th>操作</th>" +
      "</tr></thead><tbody>" +
      rows +
      "</tbody></table>";
    var btns = elAS.tableWrap.querySelectorAll("button[data-action]");
    for (var i = 0; i < btns.length; i++) {
      btns[i].addEventListener("click", onAssignmentAction);
    }
  }

  function onAssignmentAction(e) {
    var btn = e.currentTarget;
    var action = btn.getAttribute("data-action");
    if (action === "role") {
      openAssignmentRoleForm(
        btn.getAttribute("data-id"),
        btn.getAttribute("data-role")
      );
    } else if (action === "disable") {
      disableAssignment(btn.getAttribute("data-id"));
    } else if (action === "enable") {
      enableAssignment(
        btn.getAttribute("data-resident"),
        btn.getAttribute("data-caregiver"),
        btn.getAttribute("data-role")
      );
    }
  }

  function assignmentFormError(msg) {
    if (!elAS.formStatus) return;
    elAS.formStatus.textContent = msg || "";
    elAS.formStatus.classList.toggle("error", !!msg);
  }

  function closeAssignmentForm() {
    if (elAS.overlay) elAS.overlay.classList.add("hidden");
  }

  // 以後端真資料填 select：住民＝GET /api/admin/elders、照護人員＝GET /api/admin/caregivers。
  // 不以假資料補；任一來源為空 → 清楚提示需先建立資料並停用送出。
  function populateAssignmentSelects(onReady) {
    elAS.fResident.innerHTML = '<option value="">載入中…</option>';
    elAS.fCaregiver.innerHTML = '<option value="">載入中…</option>';
    if (elAS.save) elAS.save.disabled = true;
    var elders = null;
    var caregivers = null;

    function tryFinish() {
      if (elders === null || caregivers === null) return;
      var problems = [];
      if (!elders.length) problems.push("請先到「健康分析」確認已有住民資料");
      if (!caregivers.length) problems.push("請先在「照護人員管理」新增照護人員");
      if (problems.length) {
        elAS.fResident.innerHTML = elders.length
          ? residentOptions(elders)
          : '<option value="">尚無住民</option>';
        elAS.fCaregiver.innerHTML = caregivers.length
          ? caregiverOptions(caregivers)
          : '<option value="">尚無照護人員</option>';
        assignmentFormError("無法建立授權：" + problems.join("；") + "。");
        if (elAS.save) elAS.save.disabled = true;
        return;
      }
      elAS.fResident.innerHTML = residentOptions(elders);
      elAS.fCaregiver.innerHTML = caregiverOptions(caregivers);
      if (elAS.save) elAS.save.disabled = false;
      if (onReady) onReady();
    }

    fetch(adminUrl("/elders"), { headers: adminAuthHeaders() })
      .then(function (r) {
        if (r.status === 401) {
          handleSessionExpired();
          throw new Error("session_expired");
        }
        if (r.status === 403) throw new Error("forbidden");
        if (!r.ok) throw new Error("HTTP " + r.status);
        return r.json();
      })
      .then(function (data) {
        elders = Array.isArray(data) ? data : [];
        tryFinish();
      })
      .catch(function (err) {
        elders = [];
        if (err && err.message === "session_expired") {
          assignmentFormError(SESSION_EXPIRED_MSG);
        } else if (err && err.message === "forbidden") {
          assignmentFormError(FORBIDDEN_MSG);
        } else {
          assignmentFormError("讀不到住民清單，請稍後再試。");
        }
        tryFinish();
      });

    fetch(adminUrl("/caregivers"), { headers: adminAuthHeaders() })
      .then(function (r) {
        if (r.status === 401) {
          handleSessionExpired();
          throw new Error("session_expired");
        }
        if (r.status === 403) throw new Error("forbidden");
        if (!r.ok) throw new Error("HTTP " + r.status);
        return r.json();
      })
      .then(function (body) {
        caregivers =
          body && Array.isArray(body.caregivers)
            ? body.caregivers.filter(function (c) {
                return c.status === "active";
              })
            : [];
        tryFinish();
      })
      .catch(function (err) {
        caregivers = [];
        if (err && err.message === "session_expired") {
          assignmentFormError(SESSION_EXPIRED_MSG);
        } else if (err && err.message === "forbidden") {
          assignmentFormError(FORBIDDEN_MSG);
        }
        tryFinish();
      });
  }

  function residentOptions(elders) {
    return (
      '<option value="">請選擇住民</option>' +
      elders
        .map(function (e) {
          return (
            '<option value="' +
            escapeHtml(e.elderId) +
            '">' +
            escapeHtml(e.displayName || e.elderId) +
            "</option>"
          );
        })
        .join("")
    );
  }

  function caregiverOptions(caregivers) {
    return (
      '<option value="">請選擇照護人員</option>' +
      caregivers
        .map(function (c) {
          return (
            '<option value="' +
            escapeHtml(c.id) +
            '">' +
            escapeHtml(c.displayName || c.emailMasked || c.id) +
            "</option>"
          );
        })
        .join("")
    );
  }

  // 新增授權：選 住民 + 照護人員 + 角色。
  function openAssignmentForm() {
    if (isCaregiverMode() || !getAdminToken()) {
      setAssignmentsStatus(NEED_ADMIN_MSG, "error");
      return;
    }
    if (elAS.form) elAS.form.reset();
    assignmentFormError("");
    elAS.fId.value = "";
    elAS.fRole.value = "primary";
    elAS.fResident.disabled = false;
    elAS.fCaregiver.disabled = false;
    elAS.formTitle.textContent = "新增授權指派";
    if (elAS.overlay) elAS.overlay.classList.remove("hidden");
    populateAssignmentSelects();
  }

  // 改角色：沿用同一表單，鎖住民 / 照護人員 select，只改角色（PATCH 只支援 role）。
  function openAssignmentRoleForm(id, role) {
    if (!id) return;
    if (isCaregiverMode() || !getAdminToken()) {
      setAssignmentsStatus(NEED_ADMIN_MSG, "error");
      return;
    }
    assignmentFormError("");
    elAS.fId.value = id;
    elAS.fRole.value = ROLE_LABELS[role] ? role : "primary";
    elAS.fResident.innerHTML = '<option value="">（沿用原住民）</option>';
    elAS.fCaregiver.innerHTML = '<option value="">（沿用原照護人員）</option>';
    elAS.fResident.disabled = true;
    elAS.fCaregiver.disabled = true;
    if (elAS.save) elAS.save.disabled = false;
    elAS.formTitle.textContent = "修改授權角色";
    if (elAS.overlay) elAS.overlay.classList.remove("hidden");
  }

  function submitAssignmentForm(e) {
    if (e) e.preventDefault();
    if (isCaregiverMode() || !getAdminToken()) {
      assignmentFormError(NEED_ADMIN_MSG);
      return;
    }
    var id = (elAS.fId.value || "").trim();
    var role = elAS.fRole.value;
    if (id) {
      // 修改角色（PATCH，只送 role）。
      submitProvisioning(
        adminUrl("/resident-caregiver-links/" + encodeURIComponent(id)),
        "PATCH",
        { role: role },
        LINK_ERROR_MSG,
        assignmentFormError,
        function () {
          closeAssignmentForm();
          loadAssignments();
        }
      );
      return;
    }
    var residentId = elAS.fResident.value;
    var caregiverId = elAS.fCaregiver.value;
    if (!residentId || !caregiverId) {
      assignmentFormError("請選擇住民與照護人員。");
      return;
    }
    submitProvisioning(
      adminUrl("/resident-caregiver-links"),
      "POST",
      { residentId: residentId, caregiverId: caregiverId, role: role },
      LINK_ERROR_MSG,
      assignmentFormError,
      function () {
        closeAssignmentForm();
        loadAssignments(); // 建立成功後刷新列表。
      }
    );
  }

  // 共用：送出 provisioning 寫入請求並處理 401/403/業務錯誤。
  function submitProvisioning(url, method, payload, errorMap, onError, onSuccess) {
    onError("");
    fetch(url, {
      method: method,
      headers: adminJsonHeaders(),
      body: JSON.stringify(payload),
    })
      .then(function (r) {
        if (r.status === 401) {
          handleSessionExpired();
          throw new Error("session_expired");
        }
        if (r.status === 403) throw new Error("forbidden");
        return r.json().then(function (body) {
          if (!r.ok || !body || body.ok !== true) {
            throw new Error(
              "api:" + (body && body.error ? body.error : "unknown")
            );
          }
          return body;
        });
      })
      .then(function () {
        if (onSuccess) onSuccess();
      })
      .catch(function (err) {
        var msg = err && err.message ? err.message : "";
        if (msg === "session_expired") onError(SESSION_EXPIRED_MSG);
        else if (msg === "forbidden") onError(FORBIDDEN_MSG);
        else if (msg.indexOf("api:") === 0)
          onError(provisioningErrorMessage(msg.slice(4), errorMap));
        else onError("操作沒有成功，請稍後再試。");
      });
  }

  function disableAssignment(id) {
    if (!id) return;
    if (isCaregiverMode() || !getAdminToken()) {
      setAssignmentsStatus(NEED_ADMIN_MSG, "error");
      return;
    }
    if (
      !window.confirm(
        "停用後，該照護人員將不能再查看此住民的資料。\n確定要停用嗎？"
      )
    ) {
      return;
    }
    setAssignmentsStatus("更新中…", "");
    fetch(adminUrl("/resident-caregiver-links/" + encodeURIComponent(id)), {
      method: "DELETE",
      headers: adminAuthHeaders(),
    })
      .then(function (r) {
        if (r.status === 401) {
          handleSessionExpired();
          throw new Error("session_expired");
        }
        if (r.status === 403) throw new Error("forbidden");
        if (!r.ok) throw new Error("HTTP " + r.status);
        return r.json();
      })
      .then(function () {
        loadAssignments();
        setAssignmentsStatus("已停用此授權。", "");
      })
      .catch(function (err) {
        if (err && err.message === "session_expired") {
          setAssignmentsStatus(SESSION_EXPIRED_MSG, "error");
        } else if (err && err.message === "forbidden") {
          setAssignmentsStatus(FORBIDDEN_MSG, "error");
        } else {
          setAssignmentsStatus("停用沒有成功，請稍後再試。", "error");
        }
      });
  }

  // 重新啟用：後端無 re-activate 端點，以相同住民+人員+角色另建一筆 active 關聯。
  function enableAssignment(residentId, caregiverId, role) {
    if (!residentId || !caregiverId) return;
    if (isCaregiverMode() || !getAdminToken()) {
      setAssignmentsStatus(NEED_ADMIN_MSG, "error");
      return;
    }
    setAssignmentsStatus("更新中…", "");
    submitProvisioning(
      adminUrl("/resident-caregiver-links"),
      "POST",
      {
        residentId: residentId,
        caregiverId: caregiverId,
        role: ROLE_LABELS[role] ? role : "primary",
      },
      LINK_ERROR_MSG,
      function (msg) {
        setAssignmentsStatus(msg || "", "error");
      },
      function () {
        loadAssignments();
        setAssignmentsStatus("已重新啟用此授權。", "");
      }
    );
  }

  // 把目前 admin token 同步到所有分頁的權杖輸入框，存一次三頁通用。
  function syncAdminTokenInputs() {
    var token = getAdminToken();
    if (elU.adminToken) elU.adminToken.value = token;
    if (elP.adminToken) elP.adminToken.value = token;
    if (elO.adminToken) elO.adminToken.value = token;
  }

  function saveAdminTokenFrom(inputEl, reload) {
    var t = (inputEl.value || "").trim();
    localStorage.setItem(ADMIN_TOKEN_KEY, t);
    // 這些分頁（使用者 / 商品 / 訂單）為 super_admin-only，貼上管理者權杖
    // 即視為以 super_admin 身分登入。
    if (t) localStorage.setItem(AUTH_MODE_KEY, "super_admin");
    sessionInvalid = false;
    loadAuthState();
    syncAdminTokenInputs();
    applyAuthModeUi();
    if (reload) reload();
  }

  function init() {
    el.apiBase.value = getApiBase();

    // CR-0056：依 featureFlags 隱藏未正式啟用的分頁入口（marketplace / 今日任務）。
    applyFeatureFlags();

    // CR-0042：先還原身分狀態，再決定要不要打受保護 API。
    loadAuthState();

    // 身分 / 登入列（CR-0042）。
    if (elA.login) elA.login.addEventListener("click", onLoginClick);
    if (elA.logout) elA.logout.addEventListener("click", onLogoutClick);
    if (elA.firebaseEmailLogin) {
      elA.firebaseEmailLogin.addEventListener("click", onFirebaseEmailLoginClick);
    }
    if (elA.firebaseGoogleLogin) {
      elA.firebaseGoogleLogin.addEventListener("click", onFirebaseGoogleLoginClick);
    }
    if (elA.modeCaregiver) {
      elA.modeCaregiver.addEventListener("change", updateAuthHint);
    }
    if (elA.modeSuper) {
      elA.modeSuper.addEventListener("change", updateAuthHint);
    }
    // 預設選到目前模式（caregiver 為主要對象，未登入時預選照護人員）。
    if (isSuperAdminMode() && elA.modeSuper) {
      elA.modeSuper.checked = true;
    } else if (elA.modeCaregiver) {
      elA.modeCaregiver.checked = true;
    }
    updateAuthHint();
    if (hasFirebaseWebConfig()) {
      ensureFirebaseAuth().catch(function () {
        // 狀態已由 ensureFirebaseAuth 顯示；初始化失敗時保留手動權杖備援。
      });
    } else {
      updateFirebasePanelUi();
    }

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
        closeCaregiverForm();
        closeAssignmentForm();
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

    // CR-0086 長者狀態分析分頁。
    if (elAN.tab) {
      elAN.tab.addEventListener("click", function () {
        showView("analytics");
      });
    }
    if (elAN.elderSelect) {
      elAN.elderSelect.addEventListener("change", function () {
        analyticsElderId = elAN.elderSelect.value || null;
        loadResidentAnalytics();
      });
    }
    if (elAN.rangeSelect) {
      elAN.rangeSelect.addEventListener("change", function () {
        if (analyticsElderId) loadResidentAnalytics();
      });
    }
    if (elAN.refresh) {
      elAN.refresh.addEventListener("click", function () {
        // 重新整理：重抓授權長者清單；若已選長者則一併刷新其分析。
        loadAnalyticsElders();
        if (analyticsElderId) loadResidentAnalytics();
      });
    }

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

    // CR-0044 照護人員管理分頁（super_admin-only）。
    if (elCG.tab) {
      elCG.tab.addEventListener("click", function () {
        showView("caregivers");
      });
    }
    if (elCG.refresh) elCG.refresh.addEventListener("click", loadCaregivers);
    if (elCG.add) {
      elCG.add.addEventListener("click", function () {
        openCaregiverForm(null);
      });
    }
    if (elCG.form) elCG.form.addEventListener("submit", submitCaregiverForm);
    if (elCG.formClose) elCG.formClose.addEventListener("click", closeCaregiverForm);
    if (elCG.formCancel) elCG.formCancel.addEventListener("click", closeCaregiverForm);
    if (elCG.overlay) {
      elCG.overlay.addEventListener("click", function (e) {
        if (e.target === elCG.overlay) closeCaregiverForm();
      });
    }

    // CR-0044 住民授權指派分頁（super_admin-only）。
    if (elAS.tab) {
      elAS.tab.addEventListener("click", function () {
        showView("assignments");
      });
    }
    if (elAS.refresh) elAS.refresh.addEventListener("click", loadAssignments);
    if (elAS.add) {
      elAS.add.addEventListener("click", function () {
        openAssignmentForm();
      });
    }
    if (elAS.form) elAS.form.addEventListener("submit", submitAssignmentForm);
    if (elAS.formClose) elAS.formClose.addEventListener("click", closeAssignmentForm);
    if (elAS.formCancel) elAS.formCancel.addEventListener("click", closeAssignmentForm);
    if (elAS.overlay) {
      elAS.overlay.addEventListener("click", function (e) {
        if (e.target === elAS.overlay) closeAssignmentForm();
      });
    }

    syncAdminTokenInputs();
    applyAuthModeUi();

    setupGuidedTour();
    loadAlerts();
  }

  loadRuntimeConfig().then(init, init);
})();
