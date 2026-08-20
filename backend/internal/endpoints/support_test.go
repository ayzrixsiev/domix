package endpoints

// the support inbox has one property that matters more than everything else it does: **a thread is
// private to the two people in it.** it is where users paste their phone numbers, their prices and
// their problems, and every other assertion in this file is secondary to the first one.
//
// the second thing pinned here is the direction of a message. `from_support` decides which side of
// the chat a bubble is drawn on and whether it is signed "Поддержка Domix", so a request body that
// could set it would be a request body that can put words in the founder's mouth - inside the
// sender's own thread, where nobody else would ever see it to notice.

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"

	"github.com/jackc/pgx/v5"

	"domix/backend/db"
	"domix/backend/internal/auth"
)

// built on adminUnderTest for its clean slate: it deletes every user inside the transaction, and
// support_messages cascades off users - so a developer's own local conversations are not in the
// counts these tests assert on.
func supportUnderTest(t *testing.T) (*Support, *Admin, context.Context, pgx.Tx, *db.Queries) {
	t.Helper()

	adminEndpoints, ctx, tx, q := adminUnderTest(t)
	return &Support{Queries: q}, adminEndpoints, ctx, tx, q
}

// the app's side, through the real RequireAuth - the middleware is what puts the user id on the
// context, and the user id *is* the thread, so a test that skipped it would exercise nothing.
func requestSupport(
	t *testing.T, ctx context.Context, s *Support, method string, asUserID int64, body string,
) *httptest.ResponseRecorder {
	t.Helper()

	token, err := auth.GenerateJWT(asUserID, "+998900000000", testJWTSecret)
	if err != nil {
		t.Fatalf("sign a token: %v", err)
	}

	req := httptest.NewRequestWithContext(ctx, method, "/api/support/messages", strings.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")

	rec := httptest.NewRecorder()
	auth.RequireAuth(testJWTSecret, s.Queries, s.Route)(rec, req)
	return rec
}

func sendSupport(t *testing.T, ctx context.Context, s *Support, asUserID int64, text string) *httptest.ResponseRecorder {
	t.Helper()

	body, err := json.Marshal(map[string]any{"body": text})
	if err != nil {
		t.Fatalf("encode message: %v", err)
	}
	return requestSupport(t, ctx, s, http.MethodPost, asUserID, string(body))
}

func readThread(t *testing.T, ctx context.Context, s *Support, asUserID int64) []supportMessageResponse {
	t.Helper()

	rec := requestSupport(t, ctx, s, http.MethodGet, asUserID, "")
	if rec.Code != http.StatusOK {
		t.Fatalf("GET thread as %d = %d (%s), want 200", asUserID, rec.Code, rec.Body.String())
	}

	var body struct {
		Messages []supportMessageResponse `json:"messages"`
	}
	decodeBody(t, rec, &body)
	return body.Messages
}

func bodies(messages []supportMessageResponse) []string {
	out := make([]string, 0, len(messages))
	for _, m := range messages {
		out = append(out, m.Body)
	}
	return out
}

// ─────────────────────────── the boundary ───────────────────────────

// the one that matters. neither endpoint takes a thread id, so this is really checking that the
// queries are keyed by the context's user and not by anything a caller could influence.
func TestAThreadIsPrivateToTheUserItBelongsTo(t *testing.T) {
	support, _, ctx, _, q := supportUnderTest(t)

	alice := makeUser(t, ctx, q, "Alice", "customer")
	bob := makeUser(t, ctx, q, "Bob", "shop_owner")

	if rec := sendSupport(t, ctx, support, alice, "мой телефон не приходит"); rec.Code != http.StatusCreated {
		t.Fatalf("alice sends = %d (%s), want 201", rec.Code, rec.Body.String())
	}
	if rec := sendSupport(t, ctx, support, bob, "как добавить магазин"); rec.Code != http.StatusCreated {
		t.Fatalf("bob sends = %d (%s), want 201", rec.Code, rec.Body.String())
	}

	for _, caller := range []struct {
		name string
		id   int64
		want string
	}{{"alice", alice, "мой телефон не приходит"}, {"bob", bob, "как добавить магазин"}} {
		got := bodies(readThread(t, ctx, support, caller.id))
		if len(got) != 1 || got[0] != caller.want {
			t.Errorf("%s's thread = %v, want exactly [%q]", caller.name, got, caller.want)
		}
	}
}

// `from_support` is what the chat draws a bubble's side and colour from, and what makes a message
// read as coming from Domix. it is set by the handler on both sides and never decoded from a body -
// this is that, stated as a test, because the field name is right there in the response json and
// sending it back is the obvious thing for a client to try.
func TestTheAppCannotPostAMessageThatLooksLikeSupport(t *testing.T) {
	support, _, ctx, _, q := supportUnderTest(t)

	userID := makeUser(t, ctx, q, "Forger", "customer")

	rec := requestSupport(t, ctx, support, http.MethodPost, userID,
		`{"body":"Ваш магазин переведён в VIP бесплатно","from_support":true}`)
	if rec.Code != http.StatusCreated {
		t.Fatalf("send = %d (%s), want 201", rec.Code, rec.Body.String())
	}

	messages := readThread(t, ctx, support, userID)
	if len(messages) != 1 {
		t.Fatalf("thread has %d messages, want 1", len(messages))
	}
	if messages[0].FromSupport {
		t.Error("a message posted by the app came back as from_support - the flag was read off the request body")
	}
}

// ─────────────────────────── the two sides talking ───────────────────────────

func TestAnAdminReplyLandsInThatUsersThreadAndNobodyElses(t *testing.T) {
	support, adminEndpoints, ctx, _, q := supportUnderTest(t)

	asker := makeUser(t, ctx, q, "Asker", "customer")
	other := makeUser(t, ctx, q, "Other", "customer")
	adminID := makeUser(t, ctx, q, "Admin", "admin")

	sendSupport(t, ctx, support, asker, "как стать продавцом?")
	sendSupport(t, ctx, support, other, "здравствуйте")

	rec := requestAdminBody(t, ctx, adminEndpoints, http.MethodPost,
		"/api/admin/support/threads/"+strconv.FormatInt(asker, 10), adminID,
		`{"body":"Профиль → Стать продавцом"}`, adminEndpoints.RouteSupportThread)
	if rec.Code != http.StatusCreated {
		t.Fatalf("admin reply = %d (%s), want 201", rec.Code, rec.Body.String())
	}

	thread := readThread(t, ctx, support, asker)
	if len(thread) != 2 {
		t.Fatalf("asker's thread has %d messages, want 2: %v", len(thread), bodies(thread))
	}
	if thread[0].FromSupport {
		t.Error("the user's own message came back flagged as support")
	}
	if !thread[1].FromSupport {
		t.Error("the admin's reply is not flagged as support - the app would draw it as the user's own")
	}
	// ordering is by id, which for an insert-only table is the order they were written
	if thread[1].Body != "Профиль → Стать продавцом" {
		t.Errorf("last message = %q, want the reply", thread[1].Body)
	}

	if got := bodies(readThread(t, ctx, support, other)); len(got) != 1 {
		t.Errorf("the other user's thread = %v, want only their own message", got)
	}
}

// ─────────────────────────── waiting vs seen ───────────────────────────
//
// these two counts are the whole of the 000002 design and they are deliberately *not* the same
// number. the tests below are written as the pair, because either one alone would pass while the
// other silently collapsed into it.

// **reading a thread must not settle it.** this is the trade the read marker was allowed to make and
// the line it was not: opening a conversation quiets the badge, and the founder's queue keeps the
// conversation, because "I have seen this" and "this person has an answer" are different facts and
// only the second one is done.
func TestReadingAThreadClearsTheBadgeButNotTheQueue(t *testing.T) {
	support, adminEndpoints, ctx, _, q := supportUnderTest(t)

	asker := makeUser(t, ctx, q, "Asker", "customer")
	adminID := makeUser(t, ctx, q, "Admin", "admin")

	sendSupport(t, ctx, support, asker, "здравствуйте, вопрос по VIP")

	inbox := readInbox(t, ctx, adminEndpoints, adminID)
	if len(inbox) != 1 || inbox[0].Unread != 1 || inbox[0].Unanswered != 1 {
		t.Fatalf("before reading: unread=%d unanswered=%d, want 1 and 1",
			inbox[0].Unread, inbox[0].Unanswered)
	}
	if unread := readUnreadCount(t, ctx, adminEndpoints, adminID); unread != 1 {
		t.Errorf("the sidebar count is %d before reading, want 1", unread)
	}

	openThread(t, ctx, adminEndpoints, adminID, asker)

	inbox = readInbox(t, ctx, adminEndpoints, adminID)
	if inbox[0].Unread != 0 {
		t.Errorf("after reading: unread=%d, want 0 - opening the conversation is what clears this",
			inbox[0].Unread)
	}
	if inbox[0].Unanswered != 1 {
		t.Errorf("after reading: unanswered=%d, want 1 - reading is not answering, and a thread that "+
			"vanished from the queue the moment it was opened is one the founder can lose by being "+
			"interrupted", inbox[0].Unanswered)
	}
	if unread := readUnreadCount(t, ctx, adminEndpoints, adminID); unread != 0 {
		t.Errorf("the sidebar count is %d after reading, want 0", unread)
	}

	// and answering is what finally empties the queue
	requestAdminBody(t, ctx, adminEndpoints, http.MethodPost,
		"/api/admin/support/threads/"+strconv.FormatInt(asker, 10), adminID,
		`{"body":"ответил"}`, adminEndpoints.RouteSupportThread)

	inbox = readInbox(t, ctx, adminEndpoints, adminID)
	if inbox[0].Unanswered != 0 || inbox[0].Unread != 0 {
		t.Errorf("after replying: unanswered=%d unread=%d, want 0 and 0",
			inbox[0].Unanswered, inbox[0].Unread)
	}
}

// the watermark is an id, not a flag, so a message written after the read is unread by arithmetic
// rather than by something remembering to clear a bit. that is the property that keeps this from
// being the stale flag the original design refused to add.
func TestAMessageWrittenAfterTheReadIsUnreadAgain(t *testing.T) {
	support, adminEndpoints, ctx, _, q := supportUnderTest(t)

	asker := makeUser(t, ctx, q, "Asker", "customer")
	adminID := makeUser(t, ctx, q, "Admin", "admin")

	sendSupport(t, ctx, support, asker, "первый вопрос")
	openThread(t, ctx, adminEndpoints, adminID, asker)

	if unread := readUnreadCount(t, ctx, adminEndpoints, adminID); unread != 0 {
		t.Fatalf("unread=%d straight after reading, want 0", unread)
	}

	sendSupport(t, ctx, support, asker, "и ещё один")

	inbox := readInbox(t, ctx, adminEndpoints, adminID)
	if inbox[0].Unread != 1 {
		t.Errorf("a message written after the read: unread=%d, want 1", inbox[0].Unread)
	}
	if unread := readUnreadCount(t, ctx, adminEndpoints, adminID); unread != 1 {
		t.Errorf("the sidebar count is %d, want 1", unread)
	}

	// the founder's own reply does not make their own thread unread to themselves
	requestAdminBody(t, ctx, adminEndpoints, http.MethodPost,
		"/api/admin/support/threads/"+strconv.FormatInt(asker, 10), adminID,
		`{"body":"отвечаю"}`, adminEndpoints.RouteSupportThread)

	inbox = readInbox(t, ctx, adminEndpoints, adminID)
	if inbox[0].Unread != 0 {
		t.Errorf("after their own reply: unread=%d, want 0 - only what the user writes can be unread",
			inbox[0].Unread)
	}
}

// "seen" is a fact about a person, not about the conversation. there is one admin today, so this is
// pinning the model rather than a behaviour anyone will hit - and it is exactly the kind of thing
// that is free to get right now and expensive to retrofit once a second person is reading the inbox.
func TestOneAdminReadingAThreadDoesNotClearItForAnother(t *testing.T) {
	support, adminEndpoints, ctx, _, q := supportUnderTest(t)

	asker := makeUser(t, ctx, q, "Asker", "customer")
	first := makeUser(t, ctx, q, "First", "admin")
	second := makeUser(t, ctx, q, "Second", "admin")

	sendSupport(t, ctx, support, asker, "кто-нибудь?")
	openThread(t, ctx, adminEndpoints, first, asker)

	if unread := readUnreadCount(t, ctx, adminEndpoints, first); unread != 0 {
		t.Errorf("the admin who read it still counts %d unread, want 0", unread)
	}
	if unread := readUnreadCount(t, ctx, adminEndpoints, second); unread != 1 {
		t.Errorf("the other admin counts %d unread, want 1 - one person reading a message is not "+
			"everybody having read it", unread)
	}
	if inbox := readInbox(t, ctx, adminEndpoints, second); inbox[0].Unread != 1 {
		t.Errorf("the other admin's inbox shows unread=%d, want 1", inbox[0].Unread)
	}
}

// what the founder triages on. `unanswered` is derived rather than stored - a message counts as
// waiting when it is from the user and newer than the last thing support said - so the thing that
// can break is the comparison, not a flag somebody forgot to clear.
func TestTheInboxCountsWhoIsWaitingForAnAnswer(t *testing.T) {
	support, adminEndpoints, ctx, _, q := supportUnderTest(t)

	asker := makeUser(t, ctx, q, "Waiting", "customer")
	adminID := makeUser(t, ctx, q, "Admin", "admin")

	sendSupport(t, ctx, support, asker, "первый вопрос")
	sendSupport(t, ctx, support, asker, "и ещё один")

	inbox := readInbox(t, ctx, adminEndpoints, adminID)
	if len(inbox) != 1 {
		t.Fatalf("inbox has %d threads, want 1", len(inbox))
	}
	if inbox[0].Unanswered != 2 || inbox[0].Total != 2 {
		t.Errorf("before a reply: unanswered=%d total=%d, want 2 and 2", inbox[0].Unanswered, inbox[0].Total)
	}
	if inbox[0].LastFromSupport {
		t.Error("the newest message is the user's, but the inbox says it came from support")
	}

	requestAdminBody(t, ctx, adminEndpoints, http.MethodPost,
		"/api/admin/support/threads/"+strconv.FormatInt(asker, 10), adminID,
		`{"body":"отвечаю на оба"}`, adminEndpoints.RouteSupportThread)

	inbox = readInbox(t, ctx, adminEndpoints, adminID)
	if inbox[0].Unanswered != 0 {
		t.Errorf("after a reply: unanswered=%d, want 0 - one answer settles every message before it", inbox[0].Unanswered)
	}
	if !inbox[0].LastFromSupport || inbox[0].Total != 3 {
		t.Errorf("after a reply: last_from_support=%v total=%d, want true and 3", inbox[0].LastFromSupport, inbox[0].Total)
	}

	sendSupport(t, ctx, support, asker, "спасибо, ещё вопрос")
	inbox = readInbox(t, ctx, adminEndpoints, adminID)
	if inbox[0].Unanswered != 1 {
		t.Errorf("after the user writes again: unanswered=%d, want 1", inbox[0].Unanswered)
	}
}

func readInbox(t *testing.T, ctx context.Context, a *Admin, asAdminID int64) []adminSupportThreadSummary {
	t.Helper()

	rec := requestAdmin(t, ctx, a, http.MethodGet, "/api/admin/support/threads", asAdminID, a.SupportThreads)
	if rec.Code != http.StatusOK {
		t.Fatalf("inbox = %d (%s), want 200", rec.Code, rec.Body.String())
	}

	var body struct {
		Threads []adminSupportThreadSummary `json:"threads"`
	}
	decodeBody(t, rec, &body)
	return body.Threads
}

// opening a conversation the way the panel does - which is also what marks it read, since that
// request *is* the reading (see Admin.SupportThread).
func openThread(t *testing.T, ctx context.Context, a *Admin, asAdminID, threadUserID int64) {
	t.Helper()

	target := "/api/admin/support/threads/" + strconv.FormatInt(threadUserID, 10)
	rec := requestAdmin(t, ctx, a, http.MethodGet, target, asAdminID, a.RouteSupportThread)
	if rec.Code != http.StatusOK {
		t.Fatalf("open thread %d = %d (%s), want 200", threadUserID, rec.Code, rec.Body.String())
	}
}

// the number behind the sidebar badge, read off the dashboard payload the panel already fetches.
func readUnreadCount(t *testing.T, ctx context.Context, a *Admin, asAdminID int64) int64 {
	t.Helper()

	rec := requestAdmin(t, ctx, a, http.MethodGet, "/api/admin/stats", asAdminID, a.Stats)
	if rec.Code != http.StatusOK {
		t.Fatalf("stats = %d (%s), want 200", rec.Code, rec.Body.String())
	}

	var body adminStatsResponse
	decodeBody(t, rec, &body)
	return body.Support.Unread
}

// ─────────────────────────── what is not a message ───────────────────────────

func TestSupportRefusesAnEmptyMessage(t *testing.T) {
	support, _, ctx, _, q := supportUnderTest(t)

	userID := makeUser(t, ctx, q, "Blank", "customer")

	for _, text := range []string{"", "   ", "\n\t  \n"} {
		rec := sendSupport(t, ctx, support, userID, text)
		if rec.Code != http.StatusBadRequest {
			t.Errorf("sending %q = %d, want 400", text, rec.Code)
			continue
		}
		var body map[string]string
		decodeBody(t, rec, &body)
		if body["code"] != "empty_message" {
			t.Errorf("sending %q returned code %q, want empty_message", text, body["code"])
		}
	}

	if got := readThread(t, ctx, support, userID); len(got) != 0 {
		t.Errorf("thread has %d messages after only blank sends, want 0", len(got))
	}
}

// **the length limit is counted in runes and this is why it has a test.** every cyrillic letter is
// two bytes, so a byte-length check would refuse a russian message at half the limit - and the
// symptom would be "long messages fail sometimes", which is the hardest kind of bug to hear
// reported accurately.
func TestTheMessageLimitIsCountedInLettersNotBytes(t *testing.T) {
	support, _, ctx, _, q := supportUnderTest(t)

	userID := makeUser(t, ctx, q, "Longwinded", "customer")

	atTheLimit := strings.Repeat("я", supportMessageMaxRunes) // 4000 bytes, 2000 letters
	if rec := sendSupport(t, ctx, support, userID, atTheLimit); rec.Code != http.StatusCreated {
		t.Errorf("a message of exactly %d letters = %d (%s), want 201",
			supportMessageMaxRunes, rec.Code, rec.Body.String())
	}

	rec := sendSupport(t, ctx, support, userID, strings.Repeat("я", supportMessageMaxRunes+1))
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("a message one letter over the limit = %d, want 400", rec.Code)
	}
	var body map[string]string
	decodeBody(t, rec, &body)
	if body["code"] != "message_too_long" {
		t.Errorf("over the limit returned code %q, want message_too_long", body["code"])
	}
}

// the per-account guard. the general rate limiter is per-IP and allows twenty requests a second,
// which is no protection at all for an inbox a person reads by hand.
func TestOneAccountCannotFloodTheInbox(t *testing.T) {
	support, _, ctx, _, q := supportUnderTest(t)

	userID := makeUser(t, ctx, q, "Flood", "customer")

	for i := range supportMessagesPerMinute {
		if rec := sendSupport(t, ctx, support, userID, "сообщение "+strconv.Itoa(i)); rec.Code != http.StatusCreated {
			t.Fatalf("message %d = %d (%s), want 201", i, rec.Code, rec.Body.String())
		}
	}

	rec := sendSupport(t, ctx, support, userID, "ещё одно")
	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("message %d = %d, want 429", supportMessagesPerMinute+1, rec.Code)
	}
	var body map[string]string
	decodeBody(t, rec, &body)
	if body["code"] != "too_many_messages" {
		t.Errorf("over the flood limit returned code %q, want too_many_messages", body["code"])
	}
}

// ─────────────────────────── deletion ───────────────────────────

// DELETE /api/me is one statement and the schema does the rest. a support thread is the most
// personal thing in this database - it is where somebody described their problem in their own words
// - so it is the last table that may survive the account it belongs to.
func TestDeletingAnAccountTakesItsSupportMessages(t *testing.T) {
	support, _, ctx, tx, q := supportUnderTest(t)

	userID := makeUser(t, ctx, q, "Leaving", "customer")
	sendSupport(t, ctx, support, userID, "удалите мой аккаунт, пожалуйста")

	if n := countRows(t, ctx, tx, "SELECT COUNT(*) FROM support_messages WHERE user_id = $1", userID); n != 1 {
		t.Fatalf("before deletion: %d messages, want 1", n)
	}

	if err := q.DeleteUser(ctx, userID); err != nil {
		t.Fatalf("delete the user: %v", err)
	}

	if n := countRows(t, ctx, tx, "SELECT COUNT(*) FROM support_messages WHERE user_id = $1", userID); n != 0 {
		t.Errorf("after deletion: %d messages left behind, want 0", n)
	}
}

// ─────────────────────────── the admin's own thread view ───────────────────────────

// replying into a thread whose owner has just deleted their account must read as a 404 the panel can
// explain, not as a foreign-key violation surfacing as a 500.
func TestReplyingToAMissingUserIs404(t *testing.T) {
	_, adminEndpoints, ctx, _, q := supportUnderTest(t)

	adminID := makeUser(t, ctx, q, "Admin", "admin")
	gone := makeUser(t, ctx, q, "Gone", "customer")
	if err := q.DeleteUser(ctx, gone); err != nil {
		t.Fatalf("delete the user: %v", err)
	}

	target := "/api/admin/support/threads/" + strconv.FormatInt(gone, 10)

	rec := requestAdminBody(t, ctx, adminEndpoints, http.MethodPost, target, adminID,
		`{"body":"вы ещё здесь?"}`, adminEndpoints.RouteSupportThread)
	if rec.Code != http.StatusNotFound {
		t.Errorf("replying to a deleted user = %d (%s), want 404", rec.Code, rec.Body.String())
	}

	if rec := requestAdmin(t, ctx, adminEndpoints, http.MethodGet, target, adminID, adminEndpoints.RouteSupportThread); rec.Code != http.StatusNotFound {
		t.Errorf("reading a deleted user's thread = %d, want 404", rec.Code)
	}
}
