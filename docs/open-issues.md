# Open issues

Known limitations of the artefact, recorded for the dissertation rather than fixed yet. Each
entry states what happens, why the obvious fix does not work, and what would settle it.

## Event identity depends on the player's name

`MatchEvent.id` joins minute, stoppage, kind, team and player. During a live match the vendor
often reports an event without a name and fills it in later, or corrects the minute. The
identifier then changes between polls, the view model sees a new event, and the same occurrence
can be narrated twice.

It happened on 8 October 2026 (Náutico x Novorizontino, Sportmonks). A substitution already
narrated with both names came back for about a minute with the names empty, and was narrated a
second time as "Substituição no Timbu." beside the two named ones. The vendor's own identifier for
that event never changed; only the names went missing and returned.

Dropping the player from the identifier does not solve it. Two substitutions by the same team in
the same minute are common, and without the player they would share an identifier, so the second
would never be narrated.

Sportmonks gives every event an `id` that stays the same across responses, and the app does not
read it: `SportmonksEvent` has no such field. Using it as the identity of events from that vendor
would remove the duplicate without losing the second substitution. API-Football does not appear
to expose an equivalent, so its events would keep the current rule. Not done yet because it makes
the identity of an event depend on the vendor.

## The app has to stay in the foreground

A design decision, taken in November 2026: the app is a guide, used with the screen on while the
match is followed, and it does not run in the background. There is no `UIBackgroundModes` entry for
`audio`. If the listener locks the iPhone or switches to another app, it is suspended: polling
stops and nothing more is spoken.

`keepsScreenAwake` holds the screen on while narrating or waiting for the kick-off, so the
automatic lock does not trigger by itself. A deliberate lock still suspends the app.

Why it was left this way: the app is meant to be operated during the match, with gestures on the
scoreboard and replay of moments, so it is expected to be in hand. Background audio would also
need an audio session that stays active between utterances and a way to keep the polling loop
alive while suspended, which background audio alone does not guarantee.

The cost falls on blind listeners, who have no reason to keep the screen on and may put the phone in
a pocket. The evaluation is limited to people with low vision, so it does not reach this case; it
is recorded as a limit of extending the app to blind users. Evaluation participants are told to
keep the app open.

## A penalty is announced as a foul

The foul total grows first, and the vendor registers the penalty as an event only after the kick
is taken. For those seconds the listener hears "Falta" for what is a penalty. Seen on 8 October
2026 at 14 minutes. The listener in the stand had seen the penalty awarded and lost nothing, but
someone following through the app alone would not know.

Holding every foul back until it is clear that no penalty follows would delay all of them, which
is what the derived plays were designed to avoid. Nothing in the totals tells a penalty foul
apart. No fix known.

## Whose side a signal belongs to is not obvious

The vibration grammar marks the away side by repeating the pattern. A low-vision listener found
the type of event easy to tell apart and the side hard to tell from the signal alone. The
sentence that follows names the team, so nothing is lost, but the signal does not do the job it
was designed for. To be asked in the post-use questionnaire before choosing a stronger cue.

## The signals are tied to the voice

`AVSpeechService` plays the signal of each narration as it speaks it, and there is no setting
that turns the voice off while keeping the text and the vibration. A deaf or hard-of-hearing user
cannot follow with the vibrations and the on-screen list alone, although both exist. The vibrations cover only goals, cards, substitutions, missed penalties,
VAR decisions and whistles; corners, fouls and offsides have no signal, because they are too
frequent to signal. Outside the scope of the evaluation; the way to support it would be a mode with text and vibration that does
not depend on the speech service.

## Installing on participants' devices

The app requires iOS 26 and is signed with a free developer account: it must be installed from
Xcode with a cable, and the installation stops opening after seven days. Each participant's
iPhone has to be prepared by the researcher, and an installation is not durable beyond the week
of use.

## Club crests are third-party trademarks

The vendor's documentation states that logos are provided for identification only, that it holds
no rights over them, and that using them "may require additional authorization or licensing from
the respective rights holders". Fine for a research prototype; to be resolved before any public
release.

Crest requests do not count towards the daily quota but are rate limited per second and minute,
and the vendor asks for them to be cached. `AsyncImage` goes through the shared URL cache, which
covers a session but is not a guarantee across launches.

## Competition of the last and next fixtures

With API-Football, `fixtures?team=755&last=1` and `next=1` return fixtures from any competition,
and `APIFootballMapper.competition(fromLeagueID:)` maps unknown leagues to Série B. If Náutico's
next match were in a cup, the screen would call it Série B. In 2026 Náutico plays only Série B,
so this is latent rather than visible. The Sportmonks provider is not affected: it asks for the
Série B league only.

## Polling interval and the request allowance

Live narration polls every 3.5 seconds with Sportmonks and every 5 seconds with API-Football. The
wait between the scheduled kick-off and the vendor reporting the match started polls every 15
seconds.

The interval is the vendor's cadence made as fine as the plan allows. With Sportmonks it is about
1,030 requests an hour for the narration, plus about 340 for the recorder, which asks on every
third poll: some 1,370 of the 2,000 an hour that the Starter plan allows per entity. The allowance
belongs to the token, not to the phone, so **a second phone narrating the same match on the same
token exceeds it**, and both would start receiving quota errors. One phone per token during a
match.

How late the app speaks relative to the pitch was measured on 8 October 2026 from a recording of
the vendor's responses (every 30 seconds, so with an uncertainty of about 45 seconds): team totals
reached the app roughly 20 seconds after the play, events roughly 45, text comments roughly 100.
Goals were heard in the stadium between 70 and 75 seconds after they happened. The full table is
in the development diary.
