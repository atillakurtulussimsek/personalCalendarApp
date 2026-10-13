package handlers

import (
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/atillasimsek/personal-calendar/backend/internal/httpx"
	"github.com/atillasimsek/personal-calendar/backend/internal/model"
)

// exportICS handles GET /calendars/{id}/export.ics and GET /export.ics:
// every live event (masters with RRULE, exceptions as RECURRENCE-ID) as iCalendar.
func (h *Handlers) exportICS(w http.ResponseWriter, r *http.Request) {
	userID := httpx.UserID(r.Context())
	calID := ""
	if strings.Contains(r.URL.Path, "/calendars/") {
		id, err := idParam(r)
		if err != nil {
			httpx.WriteError(w, err)
			return
		}
		if _, err := h.Store.GetCalendar(r.Context(), userID, id); err != nil {
			httpx.WriteError(w, mapErr(err))
			return
		}
		calID = id
	}
	events, err := h.Store.ListEvents(r.Context(), userID, time.Date(1970, 1, 1, 0, 0, 0, 0, time.UTC), time.Date(2100, 1, 1, 0, 0, 0, 0, time.UTC))
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	var seriesIDs []string
	for _, e := range events {
		if e.Rrule != nil {
			seriesIDs = append(seriesIDs, e.ID)
		}
	}
	exceptions, err := h.Store.ListExceptions(r.Context(), userID, seriesIDs)
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	var b strings.Builder
	b.WriteString("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Personal Calendar//TR\r\nCALSCALE:GREGORIAN\r\n")
	for _, e := range events {
		if calID != "" && e.CalendarID != calID {
			continue
		}
		writeVEvent(&b, e)
	}
	for _, e := range exceptions {
		if e.DeletedAt != nil || (calID != "" && e.CalendarID != calID) {
			continue
		}
		writeVEvent(&b, e)
	}
	b.WriteString("END:VCALENDAR\r\n")
	w.Header().Set("Content-Type", "text/calendar; charset=utf-8")
	w.Header().Set("Content-Disposition", `attachment; filename="calendar.ics"`)
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(b.String()))
}

func icsTime(t time.Time) string { return t.UTC().Format("20060102T150405Z") }
func icsDate(t time.Time) string { return t.UTC().Format("20060102") }

func icsEscape(s string) string {
	r := strings.NewReplacer(`\`, `\\`, ";", `\;`, ",", `\,`, "\n", `\n`)
	return r.Replace(s)
}

// fold wraps lines at 75 octets as RFC 5545 requires.
func fold(line string) string {
	const limit = 75
	if len(line) <= limit {
		return line + "\r\n"
	}
	var out strings.Builder
	first := true
	for len(line) > 0 {
		n := limit
		if !first {
			n = limit - 1
		}
		if n > len(line) {
			n = len(line)
		}
		// do not split a UTF-8 sequence
		for n > 0 && n < len(line) && line[n]&0xC0 == 0x80 {
			n--
		}
		if !first {
			out.WriteString(" ")
		}
		out.WriteString(line[:n])
		out.WriteString("\r\n")
		line = line[n:]
		first = false
	}
	return out.String()
}

func writeVEvent(b *strings.Builder, e model.Event) {
	b.WriteString("BEGIN:VEVENT\r\n")
	b.WriteString(fold("UID:" + e.ID))
	b.WriteString(fold("DTSTAMP:" + icsTime(e.UpdatedAt)))
	if e.AllDay {
		b.WriteString(fold("DTSTART;VALUE=DATE:" + icsDate(e.StartAt)))
		b.WriteString(fold("DTEND;VALUE=DATE:" + icsDate(e.EndAt)))
	} else {
		b.WriteString(fold("DTSTART:" + icsTime(e.StartAt)))
		b.WriteString(fold("DTEND:" + icsTime(e.EndAt)))
	}
	b.WriteString(fold("SUMMARY:" + icsEscape(e.Title)))
	if e.Description != "" {
		b.WriteString(fold("DESCRIPTION:" + icsEscape(e.Description)))
	}
	if e.Location != "" {
		b.WriteString(fold("LOCATION:" + icsEscape(e.Location)))
	}
	if e.Rrule != nil {
		b.WriteString(fold("RRULE:" + *e.Rrule))
	}
	if e.RecurrenceID != nil && e.OriginalStart != nil {
		b.WriteString(fold("RECURRENCE-ID:" + icsTime(*e.OriginalStart)))
		// the UID of an exception must match its master
		b.WriteString(fold("RELATED-TO:" + *e.RecurrenceID))
	}
	for _, m := range e.Reminders {
		b.WriteString("BEGIN:VALARM\r\nACTION:DISPLAY\r\nDESCRIPTION:Reminder\r\n")
		fmt.Fprintf(b, "TRIGGER:-PT%dM\r\n", m)
		b.WriteString("END:VALARM\r\n")
	}
	b.WriteString("END:VEVENT\r\n")
}
