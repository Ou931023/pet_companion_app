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

  function adminUrl(path) {
    return getApiBase() + "/admin" + path;
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
        localStorage.setItem(
          ADMIN_TOKEN_KEY,
          (elU.adminToken.value || "").trim()
        );
        loadUsers();
      });
    }
    if (elU.usersRefresh) {
      elU.usersRefresh.addEventListener("click", loadUsers);
    }

    loadAlerts();
  }

  init();
})();
