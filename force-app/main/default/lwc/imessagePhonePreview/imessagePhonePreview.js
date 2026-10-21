import { LightningElement, api } from "lwc";

/**
 * Draws the iPhone next to the editor. The numbers here are the ones measured
 * off stock iOS 26 screenshots for the app itself (bubble body 20pt from the
 * edge, 70.6% max width, 4pt between bubbles from one sender and 15pt when the
 * sender changes), so what you build here matches what ships.
 */

export default class ImessagePhonePreview extends LightningElement {
  @api mode = "call";
  @api demo = {};
  @api notifications = [];
  @api conversations = [];
  /** The conversations ticked "Show in Phone", in the order the JSON emits them. */
  @api contacts = [];
  @api activeNotificationIndex = 0;
  @api activeConversation;
  /** Script index of the step being edited, so the phone can mark it. */
  @api selectedStep;

  listening = false;

  renderedCallback() {
    this.fit();
    if (this.listening) return;
    this.listening = true;
    window.addEventListener("resize", this.fit);
  }

  disconnectedCallback() {
    window.removeEventListener("resize", this.fit);
  }

  /**
   * Sizes the phone to the room it has. zoom, not transform: zoom shrinks the
   * layout box too, so a bad number here only makes the phone the wrong size —
   * it can never spill out of the column the way a transform did.
   */
  fit = () => {
    const box = this.template.querySelector(".fit");
    const phone = this.template.querySelector(".phone");
    if (!box || !phone) return;
    const h = box.clientHeight;
    const w = box.clientWidth;
    // A broken height chain reports something useless; keep the CSS default.
    if (h < 200 || w < 200) return;
    phone.style.zoom = Math.min(1.15, h / 800, w / 422).toFixed(3);
  };

  handleBubbleClick(e) {
    const step = Number(e.currentTarget.dataset.step);
    if (Number.isNaN(step)) return;
    this.dispatchEvent(new CustomEvent("selectstep", { detail: { step } }));
  }

  handleBubbleKeydown(e) {
    if (!this.isActivationKey(e)) return;
    e.preventDefault();
    this.handleBubbleClick(e);
  }

  handleRowClick(e) {
    const index = Number(e.currentTarget.dataset.index);
    if (Number.isNaN(index)) return;
    this.dispatchEvent(new CustomEvent("selectconversation", { detail: { index } }));
  }

  handleRowKeydown(e) {
    if (!this.isActivationKey(e)) return;
    e.preventDefault();
    this.handleRowClick(e);
  }

  isActivationKey(event) {
    return event.key === "Enter" || event.key === " ";
  }

  get isPhone() { return this.mode === "phone"; }
  get isCall() { return this.mode === "call"; }
  get isThread() { return this.mode === "thread"; }
  get isList() { return this.mode === "list"; }

  /**
   * The call screen belongs to a contact now, not to the demo. Preview the
   * contact whose call the banner belongs to; a banner in the shared list has
   * no call of its own, so fall back to the thread it opens, then to the top of
   * Favorites.
   */
  get callContact() {
    const contacts = this.contacts || [];
    const banner = this.banner;
    return contacts.find((c) => c.conversationKey === banner?.callKey)
      || contacts.find((c) => c.conversationKey === banner?.conversationKey)
      || contacts[0]
      || null;
  }

  get contactName() { return this.callContact?.contactName || "Unknown"; }
  get callSubtitle() {
    const contact = this.callContact;
    if (!contact) return "calling mobile…";
    return contact.callSubtitle || `calling ${contact.phoneLabel || "mobile"}…`;
  }
  get previewLabel() {
    if (this.isPhone) return "Phone favorites preview";
    if (this.isCall) return `Call preview for ${this.contactName}`;
    if (this.isThread) return `Conversation preview for ${this.threadName}`;
    return "Messages list preview";
  }

  /**
   * The Favorites list, numbered the way DemoConfigService numbers `contacts`,
   * so what you see here is what the phone gets.
   */
  get favorites() {
    return (this.contacts || []).map((c, i) => ({
      key: `${i}`,
      index: this.conversations.indexOf(c),
      position: i + 1,
      name: c.contactName || "Contact",
      label: c.phoneLabel || "mobile",
      ariaLabel: `Open conversation with ${c.contactName || "Contact"}`,
      avatarStyle: c.avatarUrl
        ? `background-image:url('${c.avatarUrl.replace(/'/g, "%27")}')`
        : ""
    }));
  }

  get noFavorites() { return this.favorites.length === 0; }

  get posterStyle() {
    const url = this.callContact?.callBackgroundUrl;
    return url
      ? `background-image:url('${url.replace(/'/g, "%27")}')`
      : "background:linear-gradient(#2c2c31,#131316)";
  }

  get banner() {
    const notifications = this.notifications || [];
    const n = notifications[this.activeNotificationIndex] || notifications[0];
    if (!n) return null;
    return {
      ...n,
      colorStyle: `background:${n.iconColor || "#4CD964"}`
    };
  }

  get threadName() { return this.activeConversation?.contactName || "Contact"; }

  get threadAvatarStyle() {
    const url = this.activeConversation?.avatarUrl;
    return url ? `background-image:url('${url.replace(/'/g, "%27")}')` : "";
  }

  /**
   * The demo-wide Bubble Style wins over each conversation's own checkbox, the
   * same precedence DemoConfigService applies when it builds the JSON.
   */
  get threadIsSMS() {
    const forced = this.demo?.bubbleStyle;
    if (forced === "SMS") return true;
    if (forced === "iMessage") return false;
    return this.activeConversation?.isSMS === true;
  }

  get placeholder() {
    return this.threadIsSMS ? "Text Message" : "iMessage";
  }

  /** Bubbles, with the group gaps and tails the app computes at render time. */
  get bubbles() {
    const all = this.activeConversation?.messages || [];
    // Reply counts are keyed off the position in the unfiltered script, which is
    // what "Replies to step" counts.
    const replies = {};
    all.forEach((m) => {
      const t = Number(m.replyToStep);
      if (t >= 1 && all[t - 1]) replies[t - 1] = (replies[t - 1] || 0) + 1;
    });
    const indexOf = new Map();
    all.forEach((m, i) => indexOf.set(m, i));

    return all
      .filter((m) => !m.reactToPrevious)
      .map((m, i, arr) => {
        const mine = m.sender === "me";
        const prev = arr[i - 1];
        const next = arr[i + 1];
        const sameAsPrev = prev && (prev.sender === "me") === mine;
        const lastInGroup = !next || (next.sender === "me") !== mine;
        const sms = this.threadIsSMS;
        const scriptIndex = indexOf.get(m);
        let cls = "bubble " + (mine ? (sms ? "out sms" : "out") : "in");
        if (lastInGroup) cls += " tail";
        const body = m.awaitPhoto
          ? "📷  waits for the user's real photo"
          : m.text || (m.imageUrl ? "🖼  photo" : "…");
        const target = Number(m.replyToStep);
        const quoted = target >= 1 ? all[target - 1] : null;
        const quotedMine = quoted ? quoted.sender === "me" : false;
        const count = replies[scriptIndex] || 0;

        if (scriptIndex === this.selectedStep) cls += " selected";

        return {
          key: `${i}`,
          scriptIndex,
          cls,
          body,
          ariaLabel: `Step ${scriptIndex + 1}: ${body}`,
          selected: scriptIndex === this.selectedStep,
          placeholder: m.awaitPhoto,
          rowStyle: `margin-top:${i === 0 ? 0 : sameAsPrev ? 4 : 15}px`,
          rowCls: mine ? "row mine" : "row",
          quote: quoted?.text || null,
          quoteRowCls: quotedMine ? "row mine" : "row",
          replyLabel: count ? (count === 1 ? "1 reply" : `${count} replies`) : null,
          replyRowCls: mine ? "row reply-row mine" : "row reply-row"
        };
      });
  }

  get rows() {
    return (this.conversations || []).map((c, i) => ({
      key: `${i}`,
      index: i,
      name: c.contactName || "Contact",
      preview: c.lastMessagePreview || "",
      time: c.lastMessageTime || "",
      unread: (c.unreadCount || 0) > 0,
      muted: c.isMuted === true,
      forwarded: c.isForwarded === true,
      ariaLabel: `Open conversation with ${c.contactName || "Contact"}`,
      avatarStyle: c.avatarUrl
        ? `background-image:url('${c.avatarUrl.replace(/'/g, "%27")}')`
        : ""
    }));
  }
}