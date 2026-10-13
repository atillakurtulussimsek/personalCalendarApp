// Package rrule expands recurring events into concrete occurrences within a range.
package rrule

import (
	"sort"
	"time"

	lib "github.com/teambition/rrule-go"

	"github.com/atillasimsek/personal-calendar/backend/internal/model"
)

// MaxOccurrences caps the number of instances produced for a single series.
const MaxOccurrences = 1000

// Expand returns every occurrence of the given events that overlaps [from, to).
//
// Recurring masters are expanded in their own IANA timezone so that a weekly
// 09:00 Europe/Istanbul meeting stays at 09:00 across DST changes. Exception
// rows (recurrence_id + original_start) replace the occurrence they point to;
// a deleted exception removes that occurrence.
func Expand(events, exceptions []model.Event, from, to time.Time) ([]model.Occurrence, error) {
	// index exceptions by series id and original start (UTC unix nanos)
	type exKey struct {
		series string
		orig   int64
	}
	exByKey := map[exKey]model.Event{}
	for _, ex := range exceptions {
		if ex.RecurrenceID == nil || ex.OriginalStart == nil {
			continue
		}
		exByKey[exKey{*ex.RecurrenceID, ex.OriginalStart.UTC().UnixNano()}] = ex
	}

	out := []model.Occurrence{}
	for _, ev := range events {
		if ev.DeletedAt != nil || ev.RecurrenceID != nil {
			continue // tombstones and exception rows are handled via their master
		}
		if ev.Rrule == nil {
			if ev.StartAt.Before(to) && ev.EndAt.After(from) {
				out = append(out, model.Occurrence{Event: ev, OccurrenceStart: ev.StartAt, OccurrenceEnd: ev.EndAt, SeriesID: ev.ID})
			}
			continue
		}
		loc, err := time.LoadLocation(ev.Timezone)
		if err != nil {
			loc = time.UTC
		}
		opts, err := lib.StrToROptionInLocation(*ev.Rrule, loc)
		if err != nil {
			return nil, err
		}
		opts.Dtstart = ev.StartAt.In(loc)
		rule, err := lib.NewRRule(*opts)
		if err != nil {
			return nil, err
		}
		dur := ev.EndAt.Sub(ev.StartAt)
		// Occurrences that start before `from` can still overlap it, so widen the window by the duration.
		starts := rule.Between(from.Add(-dur).In(loc), to.In(loc), true)
		for i, st := range starts {
			if i >= MaxOccurrences {
				break
			}
			st = st.UTC()
			en := st.Add(dur)
			if !st.Before(to) || !en.After(from) {
				continue
			}
			if ex, ok := exByKey[exKey{ev.ID, st.UnixNano()}]; ok {
				if ex.DeletedAt != nil {
					continue
				}
				if ex.StartAt.Before(to) && ex.EndAt.After(from) {
					out = append(out, model.Occurrence{Event: ex, OccurrenceStart: ex.StartAt, OccurrenceEnd: ex.EndAt, SeriesID: ev.ID, IsException: true})
				}
				continue
			}
			out = append(out, model.Occurrence{Event: ev, OccurrenceStart: st, OccurrenceEnd: en, SeriesID: ev.ID})
		}
	}
	// Exceptions moved into the window from an occurrence outside it.
	for _, ex := range exceptions {
		if ex.DeletedAt != nil || ex.RecurrenceID == nil || ex.OriginalStart == nil {
			continue
		}
		if !ex.StartAt.Before(to) || !ex.EndAt.After(from) {
			continue
		}
		already := false
		for _, o := range out {
			if o.IsException && o.ID == ex.ID {
				already = true
				break
			}
		}
		if !already {
			out = append(out, model.Occurrence{Event: ex, OccurrenceStart: ex.StartAt, OccurrenceEnd: ex.EndAt, SeriesID: *ex.RecurrenceID, IsException: true})
		}
	}
	sort.SliceStable(out, func(i, j int) bool { return out[i].OccurrenceStart.Before(out[j].OccurrenceStart) })
	return out, nil
}
