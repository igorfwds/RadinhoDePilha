# Open issues

Known limitations of the artefact, recorded for the dissertation rather than fixed yet. Each
entry states what happens, why the obvious fix does not work, and what would settle it.

## Event identity depends on the player's name

`MatchEvent.id` joins minute, stoppage, kind, team and player. During a live match the vendor
often reports a goal without a scorer and fills the name in later, or corrects the minute. The
identifier then changes between polls, the view model sees a new event, and the same goal can be
narrated twice.

Dropping the player from the identifier does not solve it. Two substitutions by the same team in
the same minute are common, and without the player they would share an identifier, so the second
would never be narrated.

A proper fix needs an identity the vendor keeps stable, which API-Football does not appear to
expose for events, or a reconciliation step that recognises an updated event as the same one
(same team, kind and approximate minute, with a field going from empty to filled). To be observed
in the Náutico x Sport match of 26 September 2026 (fixture 1520896) before choosing.

## Narration stops when the phone is locked

There is no `UIBackgroundModes` entry for `audio`. If the listener locks the iPhone with the side
button, the app is suspended: polling stops and nothing more is spoken. `keepsScreenAwake` only
prevents the automatic lock; it cannot prevent a deliberate one.

For the target audience this matters more than usual. A blind listener has no reason to keep the
screen on, and locking it is the natural way to put the phone in a pocket. Background audio would
need the capability, an audio session that stays active between utterances, and a way to keep the
polling loop alive while suspended, which background audio alone does not guarantee.

## Club crests are third-party trademarks

The vendor's documentation states that logos are provided for identification only, that it holds
no rights over them, and that using them "may require additional authorization or licensing from
the respective rights holders". Fine for a research prototype; to be resolved before any public
release.

Crest requests do not count towards the daily quota but are rate limited per second and minute,
and the vendor asks for them to be cached. `AsyncImage` goes through the shared URL cache, which
covers a session but is not a guarantee across launches.

## Competition of the last and next fixtures

`fixtures?team=755&last=1` and `next=1` return fixtures from any competition, and
`APIFootballMapper.competition(fromLeagueID:)` maps unknown leagues to Série B. If Náutico's next
match were in a cup, the screen would call it Série B. In 2026 Náutico plays only Série B, so this
is latent rather than visible.

## Polling interval

Live narration polls every 15 seconds, the vendor's refresh interval. Polling faster adds no detail,
since the data changes at most that often, but it lowers the average delay between the vendor
recording an event and the app speaking it: about 7.5 seconds at 15 seconds, about 2.5 at 5. On the
Pro plan a 5-second interval costs about 1,300 requests a match, against 7,500 a day and 300 a
minute. Not changed on the day of the first live test.
