import { defaultFetcher } from "@literate.ink/utilities";
import { decode } from "html-entities";
import {
  AccountKind,
  GradeKind,
  TabLocation,
  assignmentsFromIntervals,
  assignmentStatus,
  clearPresenceInterval,
  createSessionHandle,
  discussionMessages,
  discussionSendMessage,
  discussions,
  frequency,
  gradebookPDF,
  gradesOverview,
  loginQrCode,
  loginToken,
  menus,
  news,
  newsRead,
  notebook,
  parseTimetable,
  resourcesFromIntervals,
  startPresenceInterval,
  timetableFromIntervals,
  translateToWeekNumber,
} from "pawnote";
import readline from "node:readline";

// PRONOTE 2026.2.8 émet `Start({...});} catch`, ce point-virgule fait échouer le parseur de Pawnote.
const patchedFetcher = async (options) => {
  const res = await defaultFetcher(options);
  if (typeof res.content === "string" && res.content.includes("Start") && res.content.includes("catch")) {
    res.content = res.content.replace(/\);\s*\}\s*catch/g, ")}catch");
  }
  return res;
};

let activeSession = null;
let activeCredentials = null;
const discussionCache = new Map();
const newsCache = new Map();

const MIN_REQUEST_GAP_MS = 1200;
let lastRequestAt = 0;
let rateLimitUntil = 0;

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function throttleAndCheckCooldown() {
  const now = Date.now();
  if (now < rateLimitUntil) {
    const remainingSec = Math.max(1, Math.ceil((rateLimitUntil - now) / 1000));
    throw new Error(`Pronote limite temporairement les requêtes — réessaie dans ${remainingSec} s.`);
  }
  const elapsed = now - lastRequestAt;
  if (elapsed < MIN_REQUEST_GAP_MS) {
    await sleep(MIN_REQUEST_GAP_MS - elapsed);
  }
  lastRequestAt = Date.now();
}

function buildCredentials(session, refresh, deviceUUID) {
  return {
    baseURL: refresh.url,
    username: refresh.username,
    token: refresh.token,
    deviceUUID,
    accountKind: refresh.kind,
    navigatorIdentifier: refresh.navigatorIdentifier || null,
    studentName:
      session.user?.name ||
      session.userResource?.name ||
      refresh.username,
    schoolName: session.userResource?.establishmentName || "",
  };
}

function stripHtml(raw) {
  if (!raw) return "";
  const text = String(raw)
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/p>/gi, "\n")
    .replace(/<\/li>/gi, "\n")
    .replace(/<li[^>]*>/gi, "• ")
    .replace(/<[^>]+>/g, "");
  return decode(text)
    .replace(/\u00A0/g, " ")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function mapAttachments(list) {
  return (list || [])
    .filter((a) => a && a.url)
    .map((a) => ({
      id: String(a.id || a.url),
      name: String(a.name || "Fichier"),
      url: String(a.url),
      kind: Number(a.kind ?? 1),
    }));
}

function formatGradeValue(gv) {
  if (!gv) return { display: "–", numeric: null };
  switch (gv.kind) {
    case GradeKind.Grade: {
      const val = Number(gv.points);
      const display = Number.isInteger(val) ? String(val) : val.toFixed(2).replace(/\.?0+$/, "");
      return { display, numeric: val };
    }
    case GradeKind.Absent:
      return { display: "Abs.", numeric: null };
    case GradeKind.Exempted:
      return { display: "Disp.", numeric: null };
    case GradeKind.NotGraded:
      return { display: "N.Not", numeric: null };
    case GradeKind.Unfit:
      return { display: "Inapt.", numeric: null };
    case GradeKind.Unreturned:
      return { display: "N.Rendu", numeric: null };
    case GradeKind.AbsentZero:
      return { display: "Abs. (0)", numeric: 0 };
    case GradeKind.UnreturnedZero:
      return { display: "N.Rendu (0)", numeric: 0 };
    case GradeKind.Congratulations:
      return { display: "Félic.", numeric: null };
    default:
      return { display: "–", numeric: null };
  }
}

function mapCourse(item) {
  let subject = "Cours";
  let teacher = null;
  let room = null;
  let groups = [];
  let status = null;
  let isCancelled = false;
  let isModified = false;
  let isOuting = false;

  if (item.is === "lesson") {
    subject = item.subject?.name || "Cours";
    teacher = item.teacherNames?.length ? item.teacherNames.join(", ") : null;
    room = item.classrooms?.length ? item.classrooms.join(", ") : null;
    groups = Array.isArray(item.groupNames) ? item.groupNames.filter(Boolean) : [];
    status = item.status || null;
    isCancelled = Boolean(item.canceled);
    isModified = Boolean(status && status.toLowerCase().includes("modif"));
  } else if (item.is === "activity") {
    subject = item.title || "Activité";
    teacher = item.attendants?.length ? item.attendants.join(", ") : null;
    isOuting = true;
  } else if (item.is === "detention") {
    subject = item.title || "Retenue";
    teacher = item.teacherNames?.length ? item.teacherNames.join(", ") : null;
    room = item.classrooms?.length ? item.classrooms.join(", ") : null;
  }

  return {
    id: String(item.id),
    subject,
    teacher,
    room,
    groups,
    startISO: new Date(item.startDate).toISOString(),
    endISO: new Date(item.endDate).toISOString(),
    colorHex: item.backgroundColor || null,
    status,
    isCancelled,
    isModified,
    isOuting,
    memo: item.notes || null,
  };
}

function mapMealSections(meal) {
  if (!meal) return [];
  const sections = [
    ["Entrée", meal.entry],
    ["Plat", meal.main],
    ["Accompagnement", meal.side],
    ["Fromage", meal.fromage],
    ["Dessert", meal.dessert],
    ["Boisson", meal.drink],
  ];
  return sections
    .filter(([, dishes]) => Array.isArray(dishes) && dishes.length > 0)
    .map(([category, dishes]) => ({
      category,
      dishes: dishes.map((d) => ({
        name: String(d.name || ""),
        labels: (d.labels || []).map((l) => String(l.name || "")).filter(Boolean),
      })),
    }));
}

function clearActiveSession() {
  if (activeSession) {
    try {
      clearPresenceInterval(activeSession);
    } catch {
      // Ignore cleanup errors
    }
  }
  activeSession = null;
  activeCredentials = null;
  discussionCache.clear();
  newsCache.clear();
}

async function ensureTokenSession(creds) {
  if (activeSession) {
    return;
  }
  const session = createSessionHandle(patchedFetcher);
  const refresh = await loginToken(session, {
    url: creds.baseURL,
    username: creds.username,
    token: creds.token,
    kind: creds.accountKind ?? AccountKind.STUDENT,
    deviceUUID: creds.deviceUUID,
    navigatorIdentifier: creds.navigatorIdentifier || undefined,
  });
  activeSession = session;
  activeCredentials = buildCredentials(session, refresh, creds.deviceUUID);
}

async function withSession(creds, fn) {
  await throttleAndCheckCooldown();
  try {
    await ensureTokenSession(creds);
    return await fn();
  } catch (err) {
    if (err?.name === "SessionExpiredError") {
      const retryCreds = activeCredentials ?? creds;
      clearActiveSession();
      await throttleAndCheckCooldown();
      await ensureTokenSession(retryCreds);
      return await fn();
    }
    const msg = String(err?.message || "").toLowerCase();
    if (err?.name === "RateLimitedError" || err?.name === "SuspendedIPError" || msg.includes("rate-limited") || msg.includes("suspended")) {
      rateLimitUntil = Date.now() + 300_000;
      throw new Error("IP temporairement limitée par Pronote — pause automatique de 5 min activée (ne force pas l'actualisation).");
    }
    throw err;
  }
}

function selectPeriod(tab, requestedPeriodID) {
  const periods = tab?.periods || [];
  if (!periods.length) return { periods: [], selected: null };
  const selected =
    periods.find((p) => p.id === requestedPeriodID) ||
    tab.defaultPeriod ||
    periods[0];
  return { periods, selected };
}

async function handleRequest(input) {
  if (input.action === "login_qr") {
    clearActiveSession();
    const session = createSessionHandle(patchedFetcher);
    const refresh = await loginQrCode(session, {
      deviceUUID: input.deviceUUID,
      pin: input.pin,
      qr: input.qr,
    });
    activeSession = session;
    activeCredentials = buildCredentials(session, refresh, input.deviceUUID);
    return { ok: true, credentials: activeCredentials };
  }

  if (input.action === "timetable") {
    const creds = activeCredentials ?? input.credentials;
    return await withSession(creds, async () => {
      const fromDate = new Date(input.fromISO);
      const toDate = new Date(input.toISO);
      const timetable = await timetableFromIntervals(activeSession, fromDate, toDate);
      parseTimetable(activeSession, timetable, {
        withSuperposedCanceledClasses: false,
        withCanceledClasses: true,
        withPlannedClasses: true,
      });
      const weekLabels = {};
      try {
        const firstMonday = activeSession.instance?.firstMonday;
        if (firstMonday) {
          const cursor = new Date(fromDate);
          while (cursor <= toDate) {
            const wk = translateToWeekNumber(cursor, firstMonday);
            const label = frequency(activeSession, wk)?.label || null;
            if (label) {
              const yyyy = cursor.getFullYear();
              const mm = String(cursor.getMonth() + 1).padStart(2, "0");
              const dd = String(cursor.getDate()).padStart(2, "0");
              weekLabels[`${yyyy}-${mm}-${dd}`] = label;
            }
            cursor.setDate(cursor.getDate() + 7);
          }
        }
      } catch {
        // Ignore frequency lookup errors
      }
      return {
        ok: true,
        credentials: activeCredentials,
        weekLabels,
        courses: (timetable.classes || []).map(mapCourse),
      };
    });
  }

  if (input.action === "assignments") {
    const creds = activeCredentials ?? input.credentials;
    return await withSession(creds, async () => {
      const now = new Date();
      const fromDate = input.fromISO
        ? new Date(input.fromISO)
        : new Date(now.getTime() - 7 * 86400_000);
      const toDate = input.toISO
        ? new Date(input.toISO)
        : new Date(now.getTime() + 30 * 86400_000);
      const list = await assignmentsFromIntervals(activeSession, fromDate, toDate);
      const mapped = list
        .map((a) => ({
          id: String(a.id),
          subject: a.subject?.name || "Matière",
          description: stripHtml(a.description),
          colorHex: a.backgroundColor || null,
          done: Boolean(a.done),
          deadlineISO: new Date(a.deadline).toISOString(),
          difficulty: Number(a.difficulty || 0),
          lengthMinutes: typeof a.length === "number" ? a.length : null,
          attachments: mapAttachments(a.attachments),
        }))
        .sort((a, b) => a.deadlineISO.localeCompare(b.deadlineISO));
      return { ok: true, credentials: activeCredentials, assignments: mapped };
    });
  }

  if (input.action === "assignment_status") {
    const creds = activeCredentials ?? input.credentials;
    return await withSession(creds, async () => {
      await assignmentStatus(activeSession, input.assignmentID, Boolean(input.done));
      return { ok: true };
    });
  }

  if (input.action === "resources") {
    const creds = activeCredentials ?? input.credentials;
    return await withSession(creds, async () => {
      const now = new Date();
      const fromDate = input.fromISO
        ? new Date(input.fromISO)
        : new Date(now.getTime() - 14 * 86400_000);
      const toDate = input.toISO
        ? new Date(input.toISO)
        : new Date(now.getTime() + 7 * 86400_000);
      const list = await resourcesFromIntervals(activeSession, fromDate, toDate);
      const mapped = list
        .map((r) => ({
          id: String(r.id),
          subject: r.subject?.name || "Matière",
          colorHex: r.backgroundColor || null,
          startISO: new Date(r.startDate).toISOString(),
          endISO: new Date(r.endDate).toISOString(),
          teachers: Array.isArray(r.teachers) ? r.teachers : [],
          groups: Array.isArray(r.groups) ? r.groups : [],
          contents: (r.contents || []).map((c) => ({
            id: String(c.id),
            title: c.title || null,
            description: stripHtml(c.description),
            attachments: mapAttachments(c.files),
          })),
        }))
        .sort((a, b) => b.startISO.localeCompare(a.startISO));
      return { ok: true, credentials: activeCredentials, resources: mapped };
    });
  }

  if (input.action === "grades") {
    const creds = activeCredentials ?? input.credentials;
    return await withSession(creds, async () => {
      const tab = activeSession.userResource?.tabs?.get(TabLocation.Grades);
      const { periods, selected } = selectPeriod(tab, input.periodID);
      if (!selected) {
        return {
          ok: true,
          credentials: activeCredentials,
          periods: [],
          selectedPeriodID: null,
          overview: { overallAverage: null, classAverage: null, subjectAverages: [], grades: [] },
        };
      }
      const ov = await gradesOverview(activeSession, selected);
      const overall = formatGradeValue(ov.overallAverage);
      const classAvg = formatGradeValue(ov.classAverage);
      const subjectAverages = (ov.subjectsAverages || []).map((sa) => {
        const stu = formatGradeValue(sa.student);
        const cls = formatGradeValue(sa.class_average);
        const outOf = formatGradeValue(sa.outOf || sa.defaultOutOf);
        return {
          id: String(sa.subject?.id || sa.subject?.name || Math.random()),
          subject: sa.subject?.name || "Matière",
          colorHex: sa.backgroundColor || null,
          studentDisplay: stu.display,
          studentNumeric: stu.numeric,
          classDisplay: cls.display,
          outOfDisplay: outOf.numeric ? outOf.display : "20",
          outOfNumeric: outOf.numeric || 20,
        };
      });
      const subjectColors = new Map();
      for (const sa of subjectAverages) {
        if (sa.colorHex) {
          subjectColors.set(sa.subject, sa.colorHex);
        }
      }

      const grades = (ov.grades || [])
        .map((g) => {
          const val = formatGradeValue(g.value);
          const outOf = formatGradeValue(g.outOf);
          const avg = formatGradeValue(g.average);
          const min = formatGradeValue(g.min);
          const max = formatGradeValue(g.max);
          const subName = g.subject?.name || "Matière";
          return {
            id: String(g.id),
            subject: subName,
            colorHex: g.subject?.backgroundColor || subjectColors.get(subName) || null,
            comment: g.comment || null,
            valueDisplay: val.display,
            valueNumeric: val.numeric,
            outOfDisplay: outOf.display,
            outOfNumeric: outOf.numeric || 20,
            classAverageDisplay: avg.display,
            minDisplay: min.display,
            maxDisplay: max.display,
            coefficient: Number(g.coefficient || 1),
            dateISO: new Date(g.date).toISOString(),
            isBonus: Boolean(g.isBonus),
          };
        })
        .sort((a, b) => b.dateISO.localeCompare(a.dateISO));

      return {
        ok: true,
        credentials: activeCredentials,
        periods: periods.map((p) => ({ id: p.id, name: p.name })),
        selectedPeriodID: selected.id,
        overview: {
          overallAverage: overall.numeric !== null ? overall.display : null,
          classAverage: classAvg.numeric !== null ? classAvg.display : null,
          subjectAverages,
          grades,
        },
      };
    });
  }

  if (input.action === "gradebook_pdf") {
    const creds = activeCredentials ?? input.credentials;
    return await withSession(creds, async () => {
      const tab =
        activeSession.userResource?.tabs?.get(TabLocation.Gradebook) ||
        activeSession.userResource?.tabs?.get(TabLocation.Grades);
      const { selected } = selectPeriod(tab, input.periodID);
      if (!selected) {
        throw new Error("Aucune période disponible pour le bulletin.");
      }
      const url = await gradebookPDF(activeSession, selected);
      return { ok: true, url };
    });
  }

  if (input.action === "notebook") {
    const creds = activeCredentials ?? input.credentials;
    return await withSession(creds, async () => {
      const tab = activeSession.userResource?.tabs?.get(TabLocation.Notebook);
      const { periods, selected } = selectPeriod(tab, input.periodID);
      if (!selected) {
        return {
          ok: true,
          credentials: activeCredentials,
          periods: [],
          selectedPeriodID: null,
          notebookData: { absences: [], delays: [], observations: [] },
        };
      }
      const nb = await notebook(activeSession, selected);
      return {
        ok: true,
        credentials: activeCredentials,
        periods: periods.map((p) => ({ id: p.id, name: p.name })),
        selectedPeriodID: selected.id,
        notebookData: {
          absences: (nb.absences || []).map((a) => ({
            id: String(a.id),
            startISO: new Date(a.startDate).toISOString(),
            endISO: new Date(a.endDate).toISOString(),
            justified: Boolean(a.justified),
            hoursMissed: Number(a.hoursMissed || 0),
            minutesMissed: Number(a.minutesMissed || 0),
            reason: a.reason || null,
          })),
          delays: (nb.delays || []).map((d) => ({
            id: String(d.id),
            dateISO: new Date(d.date).toISOString(),
            minutes: Number(d.minutes || 0),
            justified: Boolean(d.justified),
            reason: d.reason || d.justification || null,
          })),
          observations: (nb.observations || []).map((o) => ({
            id: String(o.id),
            dateISO: new Date(o.date).toISOString(),
            name: o.name || "Observation",
            subject: o.subject?.name || null,
            reason: o.reason || null,
          })),
        },
      };
    });
  }

  if (input.action === "messages") {
    const creds = activeCredentials ?? input.credentials;
    return await withSession(creds, async () => {
      let mappedDiscussions = [];
      try {
        const discRes = await discussions(activeSession);
        discussionCache.clear();
        mappedDiscussions = (discRes.items || []).map((d) => {
          const id = String(d.participantsMessageID);
          discussionCache.set(id, d);
          return {
            id,
            subject: d.subject || "(Sans objet)",
            creator: d.creator || d.recipientName || "Inconnu",
            dateISO: new Date(d.date).toISOString(),
            unreadCount: Number(d.numberOfMessagesUnread || 0),
            messageCount: Number(d.numberOfMessages || 0),
            closed: Boolean(d.closed),
          };
        });
      } catch {
        mappedDiscussions = [];
      }

      let mappedNews = [];
      try {
        const newsRes = await news(activeSession);
        newsCache.clear();
        mappedNews = (newsRes.items || []).map((n) => {
          const id = String(n.id);
          newsCache.set(id, n);
          return {
            id,
            title: n.title || "Information",
            author: n.author || "Établissement",
            category: n.category?.name || null,
            dateISO: new Date(n.creationDate || n.startDate || Date.now()).toISOString(),
            read: Boolean(n.read),
            content: n.is === "information" ? stripHtml(n.content) : "Sondage disponible sur Pronote web.",
            attachments: n.is === "information" ? mapAttachments(n.attachments) : [],
          };
        });
      } catch {
        mappedNews = [];
      }

      return {
        ok: true,
        credentials: activeCredentials,
        discussions: mappedDiscussions,
        news: mappedNews,
      };
    });
  }

  if (input.action === "discussion_messages") {
    const creds = activeCredentials ?? input.credentials;
    return await withSession(creds, async () => {
      const disc = discussionCache.get(String(input.discussionID));
      if (!disc) {
        throw new Error("Discussion introuvable, actualisez la liste des messages.");
      }
      const res = await discussionMessages(activeSession, disc, true);
      const msgs = (res.sents || []).map((m) => ({
        id: String(m.id),
        author: m.author?.name || "Moi",
        isMe: !m.author,
        dateISO: new Date(m.creationDate).toISOString(),
        content: stripHtml(m.content),
        attachments: mapAttachments(m.files),
      }));
      return { ok: true, messages: msgs };
    });
  }

  if (input.action === "discussion_send") {
    const creds = activeCredentials ?? input.credentials;
    return await withSession(creds, async () => {
      const disc = discussionCache.get(String(input.discussionID));
      if (!disc) {
        throw new Error("Discussion introuvable, actualisez la liste des messages.");
      }
      await discussionSendMessage(activeSession, disc, String(input.content || ""));
      return { ok: true };
    });
  }

  if (input.action === "news_read") {
    const creds = activeCredentials ?? input.credentials;
    return await withSession(creds, async () => {
      const item = newsCache.get(String(input.newsID));
      if (item) {
        await newsRead(activeSession, item, true);
      }
      return { ok: true };
    });
  }

  if (input.action === "menus") {
    const creds = activeCredentials ?? input.credentials;
    return await withSession(creds, async () => {
      const targetDate = input.dateISO ? new Date(input.dateISO) : new Date();
      const wm = await menus(activeSession, targetDate);
      const days = (wm.days || []).map((d) => ({
        id: new Date(d.date).toISOString(),
        dateISO: new Date(d.date).toISOString(),
        lunch: mapMealSections(d.lunch),
        dinner: mapMealSections(d.dinner),
      }));
      return {
        ok: true,
        credentials: activeCredentials,
        menusData: { days },
      };
    });
  }

  if (input.action === "logout") {
    clearActiveSession();
    return { ok: true };
  }

  throw new Error(`Action inconnue: ${input.action}`);
}

const rl = readline.createInterface({
  input: process.stdin,
  crlfDelay: Infinity,
});

rl.on("line", async (line) => {
  const trimmed = line.trim();
  if (!trimmed) return;
  try {
    const input = JSON.parse(trimmed);
    const response = await handleRequest(input);
    process.stdout.write(JSON.stringify(response) + "\n");
  } catch (err) {
    const raw = err?.message || String(err);
    const lower = raw.toLowerCase();
    const isNetworkErr =
      lower.includes("enotfound") ||
      lower.includes("econnrefused") ||
      lower.includes("etimedout") ||
      lower.includes("eai_again") ||
      lower.includes("fetch failed") ||
      lower.includes("network");
    const safeMessage = isNetworkErr
      ? "Réseau indisponible : impossible de contacter Pronote."
      : raw.replace(/https?:\/\/[^\s]+/gi, "[URL]");
    process.stdout.write(JSON.stringify({ ok: false, error: safeMessage }) + "\n");
  }
});

rl.on("close", () => {
  clearActiveSession();
  process.exit(0);
});
