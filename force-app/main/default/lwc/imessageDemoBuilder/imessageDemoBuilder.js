import { LightningElement, track, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import LightningConfirm from "lightning/confirm";
import LightningPrompt from "lightning/prompt";
import listDemos from "@salesforce/apex/DemoBuilderController.listDemos";
import loadDemo from "@salesforce/apex/DemoBuilderController.loadDemo";
import saveDemo from "@salesforce/apex/DemoBuilderController.saveDemo";
import createDemo from "@salesforce/apex/DemoBuilderController.createDemo";
import cloneDemo from "@salesforce/apex/DemoBuilderController.cloneDemo";
import deleteDemoApex from "@salesforce/apex/DemoBuilderController.deleteDemo";
import uploadImage from "@salesforce/apex/DemoImageService.uploadImage";

const SENDERS = [
  { label: "Them", value: "them" },
  { label: "Me", value: "me" }
];
const TAPBACKS = ["", "heart", "thumbsUp", "thumbsDown", "haha", "exclamation", "question"]
  .map((v) => ({ label: v || "—", value: v }));
const EFFECTS = ["", "slam", "loud", "gentle", "invisibleInk"].map((v) => ({ label: v || "—", value: v }));
const DELIVERY = ["", "delivered", "read"].map((v) => ({ label: v || "—", value: v }));
// Blank is a real choice here, not an empty state: it hands the colour back to
// each conversation's own SMS checkbox.
const BITMAP_TYPES = ["image/png", "image/jpeg", "image/heic", "image/heif", "image/gif"];
const BUBBLE_STYLES = [
  { label: "Per conversation", value: "" },
  { label: "iMessage — all blue", value: "iMessage" },
  { label: "SMS — all green", value: "SMS" }
];
// The line under the name in the Phone app, and what "calling …" falls back to.
const PHONE_LABELS = ["mobile", "iPhone", "home", "work"].map((v) => ({ label: v, value: v }));

/** Read by iOS-NativePhoneAgent only. Blank lets the app decide from the fields. */
const VOICE_CONNECTIONS = [
  { label: "Decide from the fields", value: "" },
  { label: "Agent API (Guest)", value: "agentAPI" },
  { label: "Messaging (MIAW)", value: "messaging" }
];

export default class ImessageDemoBuilder extends LightningElement {
  @track tree;
  @track demoOptions = [];
  selectedDemoId;
  activeIndex = 0;
  activeNotificationIndex = 0;
  previewMode = "phone";
  saving = false;
  wiredDemos;
  openSections = ["basics"];
  selectedStep;
  draggingIndex;
  savedSnapshot;

  senderOptions = SENDERS;
  tapbackOptions = TAPBACKS;
  effectOptions = EFFECTS;
  deliveryOptions = DELIVERY;
  bubbleStyleOptions = BUBBLE_STYLES;
  phoneLabelOptions = PHONE_LABELS;
  voiceConnectionOptions = VOICE_CONNECTIONS;

  connectedCallback() {
    window.addEventListener("beforeunload", this.handleBeforeUnload);
  }

  disconnectedCallback() {
    window.removeEventListener("beforeunload", this.handleBeforeUnload);
  }

  handleBeforeUnload = (event) => {
    if (!this.isDirty) return;
    event.preventDefault();
    event.returnValue = "";
  };

  @wire(listDemos)
  wiredList(result) {
    this.wiredDemos = result;
    if (result.data) {
      this.demoOptions = result.data.map((d) => ({ label: d.label, value: d.id }));
      if (!this.selectedDemoId && result.data.length) {
        this.selectedDemoId = (result.data.find((d) => d.isActive) || result.data[0]).id;
        this.fetchDemo();
      }
    }
  }

  async fetchDemo({ recover = true } = {}) {
    if (!this.selectedDemoId) return;
    try {
      this.tree = await loadDemo({ demoId: this.selectedDemoId });
      this.activeIndex = 0;
      this.activeNotificationIndex = 0;
      this.selectedStep = undefined;
      this.acceptSnapshot();
    } catch (e) {
      this.tree = null;
      this.savedSnapshot = null;
      if (!recover) {
        this.toast("Could not load", this.reason(e), "error");
        return;
      }
      // The selection is stale — pull the list again and take whatever is there.
      await refreshApex(this.wiredDemos);
      const first = this.demoOptions[0];
      if (first && first.value !== this.selectedDemoId) {
        this.selectedDemoId = first.value;
        await this.fetchDemo({ recover: false });
      } else {
        this.toast("Could not load", this.reason(e), "error");
      }
    }
  }

  /** Pulls whatever the org has now, for changes made outside this page. */
  async refreshFromOrg() {
    if (!(await this.confirmDiscard("refresh from the org"))) return;
    await refreshApex(this.wiredDemos);
    const stillThere = this.demoOptions.some((o) => o.value === this.selectedDemoId);
    if (!stillThere) this.selectedDemoId = this.demoOptions[0]?.value;
    await this.fetchDemo();
    this.toast("Refreshed", "Showing what the org has now.", "success");
  }

  // MARK: validation

  /**
   * Runs on every keystroke against the in-memory tree, so a broken demo shows
   * up here rather than in front of a room. Every result is advisory so unusual
   * presenter scenarios can still be saved.
   */
  get issues() {
    if (!this.tree) return [];
    const out = [];
    const warn = (m) => out.push({
      key: `w${out.length}`, severity: "warning", message: m, cls: "issue issue-warn"
    });
    // Configuration checks are advisory: a presenter may intentionally build
    // an unusual scenario and must always be able to save it.
    const err = warn;
    const range = (value, min, max, label) => {
      if (value !== undefined && value !== null && value !== "" &&
          (Number(value) < min || Number(value) > max)) {
        err(`${label} must be between ${min} and ${max}.`);
      }
    };

    const d = this.demo;
    if (!d.name?.trim()) err("Give the demo a name.");
    if (!d.configName?.trim()) err("The demo has no config name — the URL needs it.");
    range(d.signalBars, 0, 4, "Signal bars");
    range(d.wifiStrength, 0, 3, "Wi-Fi strength");
    range(d.batteryLevel, 0, 1, "Battery");

    const keys = this.conversations.map((c) => (c.conversationKey || "").trim());
    keys.forEach((k, i) => {
      const name = this.conversations[i].contactName || `Conversation ${i + 1}`;
      if (!k) err(`"${name}" has no key — nothing can link to it.`);
      else if (keys.findIndex((candidate) => candidate.toLowerCase() === k.toLowerCase()) !== i) {
        err(`Two conversations share the key "${k}".`);
      }
      if (!this.conversations[i].contactName?.trim()) err(`Conversation ${i + 1} has no contact name.`);
      if (!(this.conversations[i].messages || []).length) warn(`"${name}" has no messages.`);
      range(this.conversations[i].unreadCount, 0, 999, `"${name}" unread count`);
      range(this.conversations[i].transcriptSpeed, 1, 99999, `"${name}" transcript speed`);
      if (this.conversations[i].showInPhone) {
        range(this.conversations[i].ringSeconds, 0, 999.9, `"${name}" ring seconds`);
        range(this.conversations[i].notificationAfterSeconds, 0, 999.9, `"${name}" banner delay`);
        // The app refuses to load a config whose voice line is missing a field, so
        // say it here, before it is in front of a room.
        voiceProblems(this.conversations[i]).forEach((problem) =>
          err(`"${name}" voice line: ${problem}`));
      }
    });
    if (!this.phoneContacts.length) {
      warn("No conversation is shown in the Phone app — Favorites opens empty and no call can be placed.");
    }

    const callableKeys = this.phoneContacts.map((c) => (c.conversationKey || "").trim());
    const lastTimeByCall = {};

    this.notifications.forEach((n, i) => {
      const label = n.title || `Notification ${i + 1}`;
      if (!n.message?.trim()) warn(`"${label}" has no message text.`);
      const k = (n.conversationKey || "").trim();
      if (!k) err(`"${label}" opens nothing — give it a conversation key.`);
      else if (!keys.some((candidate) => candidate.toLowerCase() === k.toLowerCase())) {
        err(`"${label}" points at "${k}", which no conversation uses.`);
      }

      const call = (n.callKey || "").trim();
      if (call && !keys.some((candidate) => candidate.toLowerCase() === call.toLowerCase())) {
        err(`"${label}" waits for a call to "${call}", which no conversation uses.`);
      } else if (call && !callableKeys.some((c) => c.toLowerCase() === call.toLowerCase())) {
        err(`"${label}" waits for a call to "${call}", which is not in the Phone app — it can never be called.`);
      }
      range(n.afterSeconds, 0, 999.9, `"${label}" delay`);

      // The app walks each call's banners in order, so one timed before the
      // banner above it simply waits its turn.
      const at = n.afterSeconds === null || n.afterSeconds === undefined || n.afterSeconds === ""
        ? null
        : Number(n.afterSeconds);
      if (at !== null) {
        const previous = lastTimeByCall[call];
        if (previous !== undefined && at < previous) {
          warn(`"${label}" is timed before the banner above it and will not drop in until that one has.`);
        }
        lastTimeByCall[call] = at;
      }
    });

    let photoGates = 0;
    this.conversations.forEach((c) => {
      (c.messages || []).forEach((m, i) => {
        const where = `"${c.contactName || "conversation"}" step ${i + 1}`;
        if (!["me", "them"].includes(m.sender)) err(`${where} has no sender.`);
        if (m.awaitPhoto) {
          photoGates++;
          if (m.sender !== "me") err(`${where} waits for a photo but is not from you.`);
        }
        if (m.reactToPrevious && i === 0) err(`${where} reacts to a message that does not exist yet.`);
        const target = Number(m.replyToStep);
        if (m.replyToStep !== undefined && m.replyToStep !== null && m.replyToStep !== "") {
          const steps = c.messages || [];
          if (!(target >= 1) || !steps[target - 1]) {
            err(`${where} replies to step ${m.replyToStep}, which does not exist.`);
          } else if (target - 1 >= i) {
            err(`${where} replies to a step that has not been sent yet.`);
          } else if (!steps[target - 1].text?.trim()) {
            warn(`${where} quotes a step with no text — nothing will show in the quote.`);
          }
        }
        if (!m.text?.trim() && !m.imageUrl && !m.awaitPhoto && !m.reactToPrevious) {
          warn(`${where} is empty.`);
        }
        range(m.typingSeconds, 0, 999.9, `${where} typing seconds`);
        range(m.pauseSeconds, 0, 999.9, `${where} pause seconds`);
      });
    });
    if (photoGates === 0) warn("No step waits for a photo — the camera hand-off will not trigger.");
    if (photoGates > 1) err(`${photoGates} steps wait for a photo; only one is allowed.`);

    return out;
  }

  get hasIssues() { return this.issues.length > 0; }
  get errors() { return this.issues.filter((issue) => issue.severity === "error"); }
  get warnings() { return this.issues.filter((issue) => issue.severity === "warning"); }
  get hasErrors() { return this.errors.length > 0; }

  // MARK: image upload

  /** { target, index } while an upload is in flight, so only that row spins. */
  @track uploading = null;

  /**
   * `data-target` is the name of the conversation field to fill, so nothing has
   * to be mapped here. `data-index` says which conversation; without it, the
   * one that is open.
   */
  handlePickImage(e) {
    const target = e.target.dataset.target;
    const rawIndex = e.target.dataset.index;
    const index = rawIndex === undefined ? this.activeIndex : Number(rawIndex);
    const file = e.target.files?.[0];
    if (!file) return;
    if (!file.type.startsWith("image/")) {
      this.toast("Not an image", `${file.name} is ${file.type || "an unknown type"}.`, "error");
      return;
    }
    // The phone decodes with UIImage, which handles no vector formats at all.
    // An SVG uploads and previews fine here and then silently fails on device.
    if (!BITMAP_TYPES.includes(file.type)) {
      this.toast("The phone cannot read this format",
                 `${file.name} is ${file.type}. Use PNG, JPEG, HEIC or GIF.`, "error");
      return;
    }

    this.uploading = { target, index };
    const reader = new FileReader();
    reader.onload = async () => {
      try {
        // Strip the data: prefix; Apex wants raw base64.
        const base64 = String(reader.result).split(",")[1];
        const r = await uploadImage({ base64, fileName: file.name });
        const convs = [...this.conversations];
        convs[index] = { ...convs[index], [target]: r.url };
        this.tree = { ...this.tree, conversations: convs };
        this.toast("Uploaded", `${r.fileName} is now served from this org.`, "success");
      } catch (err) {
        this.toast("Upload failed", this.reason(err), "error");
      } finally {
        this.uploading = null;
      }
    };
    reader.onerror = () => {
      this.uploading = null;
      this.toast("Could not read the file", file.name, "error");
    };
    reader.readAsDataURL(file);
  }

  isUploading(target, index) {
    return this.uploading?.target === target && this.uploading?.index === index;
  }

  get uploadingAvatar() { return this.isUploading("avatarUrl", this.activeIndex); }

  // MARK: derived

  get hasTree() { return !!this.tree; }
  get demo() { return this.tree?.demo || {}; }
  get notifications() { return this.tree?.notifications || []; }
  get conversations() { return this.tree?.conversations || []; }
  get activeConversation() { return this.conversations[this.activeIndex]; }
  /**
   * Exactly what DemoConfigService puts in the JSON's `contacts`: the ticked
   * conversations, in Favorites order, numbered from 1. Favorites keeps its own
   * running order — the contact you call first is rarely the thread at the top
   * of Messages — so this is not the conversation order.
   */
  get phoneContacts() {
    return this.conversations
      .filter((c) => c.showInPhone)
      // A conversation with no requested position goes behind the ones that
      // have one, keeping the Messages order among themselves.
      .map((c, i) => ({ c, i }))
      .sort((a, b) => {
        const x = a.c.phoneSortOrder;
        const y = b.c.phoneSortOrder;
        if (x == null && y == null) return a.i - b.i;
        if (x == null) return 1;
        if (y == null) return -1;
        return x === y ? a.i - b.i : x - y;
      })
      .map(({ c }) => c);
  }

  get noPhoneContacts() { return this.phoneContacts.length === 0; }

  /**
   * Rows for the Phone app section. Everything a contact needs is editable
   * here; name and avatar are the conversation's own fields, so editing them
   * here is editing the Messages thread — one contact, one record.
   */
  get phoneContactRows() {
    const rows = this.phoneContacts;
    return rows.map((c, i) => {
      const index = this.conversations.indexOf(c);
      const who = c.contactName || `Contact ${i + 1}`;
      return {
        ...c,
        key: `${i}`,
        index,
        position: i + 1,
        displayName: who,
        subtitlePlaceholder: `calling ${c.phoneLabel || "mobile"}…`,
        threadHint: `Its conversation is “${who}” in 3. Conversations.`,
        moveUpLabel: `Move ${who} up`,
        moveDownLabel: `Move ${who} down`,
        removeLabel: `Take ${who} out of the Phone app`,
        isFirst: i === 0,
        isLast: i === rows.length - 1,
        hasVoice: Boolean((c.voiceMyDomain || "").trim()),
        voiceIsMessaging: resolvedConnection(c) === "messaging",
        voiceGreetingPlaceholder: `This is ${who}. Hi [FIRST_NAME], how can I help you today?`,
        voiceSummary: (c.voiceMyDomain || "").trim()
          ? `Voice line · ${resolvedConnection(c) === "messaging" ? "Messaging (MIAW)" : "Agent API"}`
          : "Voice line · off",
        uploadingAvatar: this.isUploading("avatarUrl", index),
        uploadingBackground: this.isUploading("callBackgroundUrl", index)
      };
    });
  }

  /** Edits a conversation from the Phone app section, by its own index. */
  handlePhoneField(e) {
    const index = Number(e.target.dataset.index);
    const field = e.target.dataset.field;
    const convs = [...this.conversations];
    convs[index] = { ...convs[index], [field]: this.fieldValue(e) };
    this.tree = { ...this.tree, conversations: convs };
  }

  /**
   * A contact is a conversation, so adding one here starts a thread too — empty
   * until you write it in 3. Conversations. That is the point: the name and the
   * avatar can then never disagree between the two tabs.
   */
  addPhoneContact() {
    const conversation = this.newConversation();
    this.tree = { ...this.tree, conversations: [...this.conversations, conversation] };
    this.toast(
      "Contact added",
      `“${conversation.contactName}” is in Favorites, and its conversation is ready to write.`,
      "success"
    );
  }

  async removePhoneContact(e) {
    const index = Number(e.currentTarget.dataset.index);
    const conversation = this.conversations[index];
    const confirmed = await LightningConfirm.open({
      label: "Take out of the Phone app",
      theme: "warning",
      message: `Take “${conversation.contactName || "this contact"}” out of Favorites? ` +
               "Its conversation stays in Messages."
    });
    if (!confirmed) return;
    const convs = [...this.conversations];
    convs[index] = { ...convs[index], showInPhone: false, phoneSortOrder: null };
    this.tree = { ...this.tree, conversations: convs };
  }
  get endpointUrl() { return this.tree?.endpointUrl; }
  get defaultUrl() { return this.tree?.defaultUrl; }
  get showDefaultUrl() {
    return !!(this.demo?.isActive && this.defaultUrl && this.defaultUrl !== this.endpointUrl);
  }
  get isDirty() {
    return !!this.tree && this.savedSnapshot !== this.snapshot(this.tree);
  }
  get saveDisabled() { return this.saving || !this.tree; }
  get actionDisabled() { return this.saving || !this.tree; }
  get duplicateDisabled() { return this.actionDisabled || this.isDirty; }
  get batteryPercent() {
    return this.demo.batteryLevel === undefined || this.demo.batteryLevel === null
      ? null
      : Math.round(Number(this.demo.batteryLevel) * 100);
  }
  get saveStateLabel() {
    if (this.saving) return "Saving…";
    const warningLabel = this.warnings.length
      ? ` · ${this.warnings.length} warning${this.warnings.length === 1 ? "" : "s"}`
      : "";
    if (this.isDirty) return `Unsaved changes${warningLabel}`;
    return this.tree ? `All changes saved${warningLabel}` : "No demo selected";
  }
  get saveStateClass() {
    if (this.isDirty) return "save-state state-dirty";
    return "save-state state-saved";
  }
  get issueSummary() {
    const errorCount = this.errors.length;
    const warningCount = this.warnings.length;
    const parts = [];
    if (errorCount) parts.push(`${errorCount} error${errorCount === 1 ? "" : "s"}`);
    if (warningCount) parts.push(`${warningCount} warning${warningCount === 1 ? "" : "s"}`);
    return parts.join(" · ");
  }
  /**
   * Only a contact in the Phone app can be called, so only those can carry
   * banners of their own. The blank entry is the demo-wide list, which is what
   * configs written before per-call banners use.
   */
  get callOptions() {
    return [
      { label: "Every call (shared list)", value: "" },
      ...this.phoneContacts.map((contact, index) => ({
        label: contact.contactName || `Contact ${index + 1}`,
        value: contact.conversationKey || ""
      }))
    ];
  }

  get conversationOptions() {
    return [
      { label: "Choose a conversation", value: "" },
      ...this.conversations.map((conversation, index) => ({
        label: conversation.contactName || `Conversation ${index + 1}`,
        value: conversation.conversationKey || ""
      }))
    ];
  }

  get conversationTabs() {
    return this.conversations.map((c, i) => ({
      key: `${i}`,
      index: i,
      label: c.contactName || "Untitled",
      cls: i === this.activeIndex ? "conv-tab is-active" : "conv-tab",
      selected: i === this.activeIndex
    }));
  }

  /** Rows carry their index so the handlers stay a one-liner. */
  get messageRows() {
    const messages = this.activeConversation?.messages || [];
    return messages.map((m, i) => ({
      ...m,
      key: `${i}`,
      index: i,
      cardCls: i === this.selectedStep ? "card msg is-selected" : "card msg",
      badge: m.awaitPhoto ? "waits for photo" : m.reactToPrevious ? `reacts ${m.reactToPrevious}` : null,
      editorLabel: `Step ${i + 1} message`,
      senderLabel: `Step ${i + 1} sender`,
      moveUpLabel: `Move step ${i + 1} up`,
      moveDownLabel: `Move step ${i + 1} down`,
      deleteLabel: `Delete step ${i + 1}`,
      isFirst: i === 0,
      isLast: i === messages.length - 1,
      replyValue: m.replyToStep ? String(m.replyToStep) : "",
      replyOptions: [
        { label: "Not a reply", value: "" },
        ...messages.slice(0, i).map((candidate, priorIndex) => ({
          label: `Step ${priorIndex + 1}: ${
            candidate.text?.trim().slice(0, 45) || (candidate.imageUrl ? "Photo" : "Untitled step")
          }`,
          value: String(priorIndex + 1)
        }))
      ]
    }));
  }

  get notificationRows() {
    return this.notifications.map((n, i) => {
      const call = this.conversations.find((c) => c.conversationKey === n.callKey);
      return {
        ...n,
        key: `${i}`,
        index: i,
        displayLabel: n.title || `Notification ${i + 1}`,
        callHint: n.callKey
          ? `During the ${call?.contactName || n.callKey} call`
          : "During every call",
        cardCls: i === this.activeNotificationIndex ? "card notification is-selected" : "card notification"
      };
    });
  }

  get previewTabs() {
    const labels = { phone: "Phone", call: "Call", thread: "Conversation", list: "Messages list" };
    return ["phone", "call", "thread", "list"].map((mode) => ({
      key: mode, mode, label: labels[mode],
      cls: mode === this.previewMode ? "pv-tab is-active" : "pv-tab",
      selected: mode === this.previewMode
    }));
  }

  // MARK: edits

  async handleDemoPick(e) {
    const nextDemoId = e.detail.value;
    if (nextDemoId === this.selectedDemoId) return;
    if (!(await this.confirmDiscard("switch demos"))) {
      const currentDemoId = this.selectedDemoId;
      this.selectedDemoId = undefined;
      await Promise.resolve();
      this.selectedDemoId = currentDemoId;
      return;
    }
    this.selectedDemoId = nextDemoId;
    await this.fetchDemo();
  }

  /** A bubble was tapped on the phone: focus the step that drew it. */
  handleSelectStep(e) {
    const step = e.detail.step;
    this.selectedStep = step;
    // Let the class land before scrolling, or the card is not laid out yet.
    Promise.resolve().then(() => {
      const card = this.template.querySelector(`.msg[data-index="${step}"]`);
      card?.scrollIntoView({ behavior: "smooth", block: "center" });
    });
  }

  handleSelectConversation(e) {
    this.activeIndex = e.detail.index;
    this.selectedStep = undefined;
    this.previewMode = "thread";
  }

  handleDragStart(e) {
    this.draggingIndex = Number(e.currentTarget.dataset.index);
    e.dataTransfer.effectAllowed = "move";
  }

  handleDragOver(e) {
    e.preventDefault();
    e.dataTransfer.dropEffect = "move";
  }

  handleDrop(e) {
    e.preventDefault();
    const to = Number(e.currentTarget.dataset.index);
    const from = this.draggingIndex;
    if (from === undefined || from === to) return;
    const msgs = this.reorderMessages(this.activeConversation.messages, from, to);
    const convs = [...this.conversations];
    convs[this.activeIndex] = { ...convs[this.activeIndex], messages: msgs };
    this.tree = { ...this.tree, conversations: convs };
    this.selectedStep = to;
    this.draggingIndex = undefined;
  }

  handleDragEnd() { this.draggingIndex = undefined; }
  handlePreviewTab(e) { this.previewMode = e.currentTarget.dataset.mode; }
  handleConvTab(e) { this.activeIndex = Number(e.currentTarget.dataset.index); this.previewMode = "thread"; }
  handlePreviewNotification(e) {
    this.activeNotificationIndex = Number(e.currentTarget.dataset.index);
    this.previewMode = "call";
  }

  fieldValue(e) {
    const t = e.target;
    if (t.type === "checkbox") return t.checked;
    const value = e.detail && e.detail.value !== undefined ? e.detail.value : t.value;
    if (t.dataset.transform === "percent") {
      return value === "" || value === null ? null : Number(value) / 100;
    }
    return value;
  }

  handleDemoField(e) {
    const f = e.target.dataset.field;
    const value = this.fieldValue(e);
    const previous = this.demo;
    const changes = { [f]: value };
    if (f === "name" &&
        (!previous.configName || previous.configName === this.slugify(previous.name))) {
      changes.configName = this.slugify(value);
    }
    this.tree = { ...this.tree, demo: { ...previous, ...changes } };
  }

  generateConfigName() {
    this.tree = {
      ...this.tree,
      demo: { ...this.demo, configName: this.slugify(this.demo.name) }
    };
  }

  handleConvField(e) {
    const f = e.target.dataset.field;
    const value = this.fieldValue(e);
    const convs = [...this.conversations];
    const previousKey = convs[this.activeIndex].conversationKey;
    convs[this.activeIndex] = { ...convs[this.activeIndex], [f]: value };
    // Joining Favorites lands you at the end; leaving it gives up your place.
    if (f === "showInPhone") {
      convs[this.activeIndex].phoneSortOrder = value
        ? this.phoneContacts.length + 1
        : null;
    }
    // A key is what notifications point at, both to open a thread and to pick
    // the call they drop into, so renaming one has to carry both along.
    const notifications = f === "conversationKey"
      ? this.notifications.map((notification) => ({
        ...notification,
        conversationKey: notification.conversationKey === previousKey
          ? value
          : notification.conversationKey,
        callKey: notification.callKey === previousKey ? value : notification.callKey
      }))
      : this.notifications;
    this.tree = { ...this.tree, conversations: convs, notifications };
  }

  handleMsgField(e) {
    const i = Number(e.target.dataset.index);
    const f = e.target.dataset.field;
    let value = this.fieldValue(e);
    if (f === "replyToStep") value = value ? Number(value) : null;
    const convs = [...this.conversations];
    const msgs = [...convs[this.activeIndex].messages];
    msgs[i] = { ...msgs[i], [f]: value };
    convs[this.activeIndex] = { ...convs[this.activeIndex], messages: msgs };
    this.tree = { ...this.tree, conversations: convs };
  }

  handleNotifField(e) {
    const i = Number(e.target.dataset.index);
    const f = e.target.dataset.field;
    const notifs = [...this.notifications];
    notifs[i] = { ...notifs[i], [f]: this.fieldValue(e) };
    this.tree = { ...this.tree, notifications: notifs };
  }

  // MARK: add / remove / reorder

  addMessage() {
    const convs = [...this.conversations];
    const msgs = [...(convs[this.activeIndex].messages || []),
      { sender: "them", text: "", sendAutomatically: true, typingSeconds: 1.2 }];
    convs[this.activeIndex] = { ...convs[this.activeIndex], messages: msgs };
    this.tree = { ...this.tree, conversations: convs };
  }

  removeMessage(e) {
    const i = Number(e.currentTarget.dataset.index);
    const convs = [...this.conversations];
    const msgs = this.removeMessageAndRepair(convs[this.activeIndex].messages, i);
    convs[this.activeIndex] = { ...convs[this.activeIndex], messages: msgs };
    this.tree = { ...this.tree, conversations: convs };
  }

  moveMessage(e) {
    const i = Number(e.currentTarget.dataset.index);
    const to = i + Number(e.currentTarget.dataset.delta);
    if (to < 0 || to >= this.activeConversation.messages.length) return;
    const msgs = this.reorderMessages(this.activeConversation.messages, i, to);
    const convs = [...this.conversations];
    convs[this.activeIndex] = { ...convs[this.activeIndex], messages: msgs };
    this.tree = { ...this.tree, conversations: convs };
  }

  /** Moves one contact in Favorites and rewrites every position to match. */
  movePhoneContact(e) {
    const from = Number(e.currentTarget.dataset.position) - 1;
    const to = from + Number(e.currentTarget.dataset.delta);
    const ordered = this.phoneContacts;
    if (to < 0 || to >= ordered.length) return;

    const moved = [...ordered];
    moved.splice(to, 0, moved.splice(from, 1)[0]);

    const positions = new Map(moved.map((c, i) => [c, i + 1]));
    this.tree = {
      ...this.tree,
      conversations: this.conversations.map((c) =>
        positions.has(c) ? { ...c, phoneSortOrder: positions.get(c) } : c
      )
    };
  }

  /** Jumps the editor to the conversation behind a Favorites row. */
  handlePhoneContactPick(e) {
    this.activeIndex = Number(e.currentTarget.dataset.index);
    this.selectedStep = undefined;
    this.previewMode = "thread";
    this.openSections = [...new Set([...this.openSections, "convs"])];
  }

  /** A blank conversation, already in Favorites at the end of the list. */
  newConversation() {
    const n = this.conversations.length + 1;
    const usedKeys = new Set(
      this.conversations.map((conversation) => (conversation.conversationKey || "").toLowerCase())
    );
    let key = `conversation-${n}`;
    let suffix = n + 1;
    while (usedKeys.has(key.toLowerCase())) key = `conversation-${suffix++}`;
    return {
      conversationKey: key, contactName: `Contact ${n}`, transcriptSpeed: 600,
      showInPhone: true, phoneLabel: "mobile", ringSeconds: 3,
      phoneSortOrder: this.phoneContacts.length + 1,
      messages: []
    };
  }

  addConversation() {
    const convs = [...this.conversations, this.newConversation()];
    this.tree = { ...this.tree, conversations: convs };
    this.activeIndex = convs.length - 1;
    this.previewMode = "thread";
  }

  async removeConversation() {
    const current = this.activeConversation;
    if (!current) return;
    const linkedNotifications = this.notifications.filter(
      (notification) => notification.conversationKey === current.conversationKey
    );
    const confirmed = await LightningConfirm.open({
      label: "Remove conversation",
      theme: "warning",
      message: linkedNotifications.length
        ? `Remove “${current.contactName || "this conversation"}” and its ${linkedNotifications.length} linked notification(s)?`
        : `Remove “${current.contactName || "this conversation"}”?`
    });
    if (!confirmed) return;
    const convs = this.conversations.filter((_, j) => j !== this.activeIndex);
    const notifications = this.notifications.filter(
      (notification) => notification.conversationKey !== current.conversationKey
    );
    this.tree = { ...this.tree, conversations: convs, notifications };
    this.activeIndex = Math.max(0, this.activeIndex - 1);
  }

  addNotification() {
    const current = this.activeConversation;
    const callable = this.phoneContacts.some(
      (contact) => contact.conversationKey === current?.conversationKey
    );
    const notifs = [...this.notifications, {
      iconName: "message.fill", iconColor: "#4CD964",
      title: current?.contactName || "", message: "", timeAgo: "now",
      conversationKey: current?.conversationKey || "",
      // Only a contact you can call can own a banner; anything else starts in
      // the shared list.
      callKey: callable ? current.conversationKey : "",
      afterSeconds: null
    }];
    this.tree = { ...this.tree, notifications: notifs };
    this.activeNotificationIndex = notifs.length - 1;
    this.previewMode = "call";
  }

  removeNotification(e) {
    const i = Number(e.currentTarget.dataset.index);
    this.tree = { ...this.tree, notifications: this.notifications.filter((_, j) => j !== i) };
    this.activeNotificationIndex = Math.max(
      0,
      Math.min(this.activeNotificationIndex, this.notifications.length - 1)
    );
  }

  // MARK: persistence

  async save() {
    this.saving = true;
    try {
      this.tree = await saveDemo({ treeJson: JSON.stringify(this.tree) });
      this.acceptSnapshot();
      await refreshApex(this.wiredDemos);
      this.toast("Saved", "The endpoint is already serving this.", "success");
    } catch (e) {
      this.toast("Could not save", this.reason(e), "error");
    } finally {
      this.saving = false;
    }
  }

  async newDemo() {
    if (!(await this.confirmDiscard("create a new demo"))) return;
    const name = await LightningPrompt.open({
      label: "Create demo",
      message: "Give the demo a clear name. Its URL key will be generated automatically.",
      defaultValue: "New demo"
    });
    if (!name?.trim()) return;
    try {
      this.selectedDemoId = await createDemo({ name: name.trim() });
      await refreshApex(this.wiredDemos);
      await this.fetchDemo();
      this.toast(
        "Created",
        this.endpointUrl
          ? `Stable URL ready — copy it from the toolbar.`
          : "The demo is ready to edit.",
        "success"
      );
    } catch (e) {
      this.toast("Could not create", this.reason(e), "error");
    }
  }

  async duplicateDemo() {
    if (this.duplicateDisabled) return;
    const name = await LightningPrompt.open({
      label: "Duplicate demo",
      message: "Create a copy with a new name and URL key.",
      defaultValue: `${this.demo.name || "Demo"} copy`
    });
    if (!name?.trim()) return;
    try {
      this.selectedDemoId = await cloneDemo({
        demoId: this.selectedDemoId,
        versionToken: this.tree.versionToken,
        name: name.trim()
      });
      await refreshApex(this.wiredDemos);
      await this.fetchDemo();
      this.toast(
        "Duplicated",
        this.endpointUrl
          ? "Copy has its own URL — use Copy in the toolbar."
          : "The copy is ready to edit.",
        "success"
      );
    } catch (e) {
      this.toast("Could not duplicate", this.reason(e), "error");
    }
  }

  async deleteDemo() {
    if (!this.tree) return;
    const confirmed = await LightningConfirm.open({
      label: "Delete demo",
      theme: "error",
      message: `Delete “${this.demo.name || "this demo"}” and everything in it? This cannot be undone.`
    });
    if (!confirmed) return;
    try {
      await deleteDemoApex({
        demoId: this.selectedDemoId,
        versionToken: this.tree.versionToken
      });
      this.selectedDemoId = null;
      this.tree = null;
      this.savedSnapshot = null;
      await refreshApex(this.wiredDemos);
      const next = this.demoOptions.find((option) => option.value !== this.selectedDemoId);
      if (next) {
        this.selectedDemoId = next.value;
        await this.fetchDemo();
      }
      this.toast("Deleted", "The demo was removed.", "success");
    } catch (e) {
      this.toast("Could not delete", this.reason(e), "error");
    }
  }

  async copyUrl() {
    await this.copyText(this.endpointUrl, "This demo’s URL");
  }

  async copyDefaultUrl() {
    await this.copyText(this.defaultUrl, "Default URL");
  }

  async copyText(value, label) {
    if (!value) return;
    try {
      await navigator.clipboard.writeText(value);
      this.toast("Copied", `${label} is on the clipboard.`, "success");
    } catch {
      this.toast("Copy it by hand", value, "info");
    }
  }

  async confirmDiscard(action) {
    if (!this.isDirty) return true;
    return LightningConfirm.open({
      label: "Unsaved changes",
      theme: "warning",
      message: `You have unsaved changes. Discard them and ${action}?`
    });
  }

  snapshot(tree) {
    return tree ? JSON.stringify(tree) : null;
  }

  acceptSnapshot() {
    this.savedSnapshot = this.snapshot(this.tree);
  }

  slugify(value) {
    const slug = String(value || "")
      .toLowerCase()
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "");
    return (slug || "new-demo").slice(0, 100);
  }

  reorderMessages(messages, from, to) {
    const entries = messages.map((message) => ({
      message,
      replyTarget: message.replyToStep ? messages[Number(message.replyToStep) - 1] : null
    }));
    const [moved] = entries.splice(from, 1);
    entries.splice(to, 0, moved);
    return entries.map((entry) => {
      const targetIndex = entry.replyTarget
        ? entries.findIndex((candidate) => candidate.message === entry.replyTarget)
        : -1;
      return { ...entry.message, replyToStep: targetIndex >= 0 ? targetIndex + 1 : null };
    });
  }

  removeMessageAndRepair(messages, removeIndex) {
    const removed = messages[removeIndex];
    const kept = messages.filter((_, index) => index !== removeIndex);
    return kept.map((message) => {
      if (!message.replyToStep) return message;
      const target = messages[Number(message.replyToStep) - 1];
      if (!target || target === removed) return { ...message, replyToStep: null };
      return { ...message, replyToStep: kept.indexOf(target) + 1 };
    });
  }

  reason(e) {
    return e?.body?.message || e?.message || "Unexpected error";
  }

  toast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}
/** What the app will use: the explicit pick, or Agent API when an Agent ID is given. */
function resolvedConnection(c) {
  if (c.voiceConnection) return c.voiceConnection;
  const hasVoiceId = Boolean((c.voiceAgentId || "").trim());
  const hasDeployment = Boolean((c.voiceEsDeveloperName || "").trim());
  return !hasVoiceId && hasDeployment ? "messaging" : "agentAPI";
}

/** Mirrors VoiceConfig.missingFields in the app. A blank My Domain means no voice line. */
function voiceProblems(c) {
  const domain = (c.voiceMyDomain || "").trim();
  const anyOther = ["voiceAgentId", "voiceEsDeveloperName", "voiceOrgId", "voiceScrtUrl"]
    .some((f) => (c[f] || "").trim());
  if (!domain) {
    return anyOther ? ["has credentials but no My Domain URL, so the call stays fake."] : [];
  }
  const problems = [];
  if (!/^https:\/\/[^/\s]+/i.test(domain)) problems.push("My Domain URL must start with https://.");
  const missing = [];
  if (resolvedConnection(c) === "messaging") {
    if (!(c.voiceEsDeveloperName || "").trim()) missing.push("Deployment API name");
    if (!(c.voiceOrgId || "").trim()) missing.push("Org ID");
    if (!(c.voiceScrtUrl || "").trim()) missing.push("SCRT URL");
  } else if (!(c.voiceAgentId || "").trim()) {
    missing.push("Agent ID");
  }
  if (missing.length) {
    problems.push(`missing ${missing.join(", ")} — the app will refuse to load this config.`);
  }
  return problems;
}
