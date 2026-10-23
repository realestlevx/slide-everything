# Roblox titles, hooks and thumbnails: discovery and click-through in 2025-2026, and whether "Slide Everything" works as a title

Research date: 2026-10-23. Sources are 2025-2026 unless they carry an [OLDER: date] label. "Cited Findings" holds only sourced material. "Inferences" holds my own analysis, including the full rubric and the alternative titles.

---

## Q1. How does Roblox discovery and recommendation work in 2025-2026, and how much do title, icon and thumbnail matter compared with engagement metrics? Does keyword search matter for new games?

### Takeaway
Home "Recommended for You" (RFY) brings most of the traffic. It ranks games mostly on per-user engagement among players who arrive organically. Play-through rate (impression to play) is now the #1 signal, and the tile (thumbnail/video plus title) controls it. Bounce rate, play days and playtime come right after, and in June 2026 Roblox widened the evaluation window to 28 days, specifically so that games which win clicks with exciting thumbnails but don't retain are not over-rewarded. In short, the title and thumbnail get a game sampled, and retention decides whether Roblox keeps showing it. Search is moving from title matching to intent matching. It is driven by "query engagement", and players search broad genre terms more than game names. So a title helps a new game mainly when it contains the words players actually type, and when it is easy to remember and spell after someone sees the game on video.

### Cited Findings
**How RFY works (Creator Hub "Discovery", live 2026 doc)**
- RFY works in two stages: *retrieval* picks a subset of games for each user based on engagement, retention and monetization, and *ranking* then orders them for that user. Its stated goal is "deep engagement, social interaction, and repeat play." — [Creator Hub: Discovery](https://create.roblox.com/docs/production/promotion/discovery)
- Explore/expand: Roblox tests a game on new user cohorts and expands distribution if they do well. "If that new user cohort has good engagement and monetization, Roblox is more likely to continue to recommend your game." — [Creator Hub: Discovery](https://create.roblox.com/docs/production/promotion/discovery)
- Cold start: sponsored ads, curation, search, charts, friends, notifications and social sharing can all bring a game into consideration for organic distribution sooner, and "even a small number of players can help." However, "Roblox doesn't count the engagement, monetization, or retention of users first acquired from ads" when ranking. — [Creator Hub: Discovery](https://create.roblox.com/docs/production/promotion/discovery)
- Ranked RFY signals, most to least important: (1) **play-through rate**, "the rate at which users play your game after seeing it in the Recommended for You sort"; (2) **first-play bounce rate** (negative; <60 s and 61-180 s); (3) play days per user (D1, D2-7, D8-28); (4) playtime per user, capped at 60 min/user/game/day; (5) intentional co-play days; (6) qualified play sessions; (7) spend days and Robux spent per user. — [Creator Hub: Discovery](https://create.roblox.com/docs/production/promotion/discovery)
- Signals are per-user averages, not totals: "Roblox is focused on per user engagement, not total engagement." An earlier announcement says "smaller experiences with highly engaged users are not disadvantaged." — [Creator Hub: Discovery](https://create.roblox.com/docs/production/promotion/discovery); [DevForum, Mar 31 2025](https://devforum.roblox.com/t/boost-your-discovery-with-the-improved-recommended-for-you-algorithm-and-analytics-for-creators/3587441)

**Timeline of signal changes**
- **Mar 31, 2025:** improved RFY launched with qPTR (engaging plays ÷ RFY impressions), 7-day per-user playtime, play days, spend days, Robux spent, intentional co-play, and the 60-minute daily playtime cap. "To improve QPTR, focusing on your thumbnail personalization strategy is key." Most signals update within 24 hours, and impressions react "a few days later." — [DevForum, Mar 31 2025](https://devforum.roblox.com/t/boost-your-discovery-with-the-improved-recommended-for-you-algorithm-and-analytics-for-creators/3587441)
- **Dec 11, 2025:** reserved-server sessions now count as intentional co-play, and attribution was fixed to RFY only. — [same thread](https://devforum.roblox.com/t/boost-your-discovery-with-the-improved-recommended-for-you-algorithm-and-analytics-for-creators/3587441)
- **Mar 9, 2026 (updated through Jul 29, 2026):** "Today's Picks" became **Standout Games**, a hand-curated sort for novel games that "will now primarily feature video previews." A "Deep play through rate" signal and a 7-day qualified-play-sessions signal were added. Ads are now "spread throughout the Recommended for You sort." From Jul 29, 2026, **gameplay videos autoplay on RFY tiles** (on hover on desktop, when scrolling stops on mobile). Roblox says this does not change ranking. Videos must show real current gameplay, with no cinematic trailers, enhanced graphics, narration or promotional text. Roblox is exploring genre sorts, "Because you played X" sorts and sorts for first-time players. — [DevForum: How we are improving Home this year](https://devforum.roblox.com/t/how-we-are-improving-home-this-year/4502571)
- **Jun 15, 2026:** RFY signals expanded "from 7 days to 28 days" (D1, D2-7, D8-28). **qPTR was removed** and replaced with **PTR plus first-play bounce rates**, so that play-through, session quality and retention are measured separately. Roblox will test switching thumbnail personalization to PTR. The post gives no cold-start or grace-period rules for new games, and commenters raised this without an answer. — [DevForum, Jun 15 2026](https://devforum.roblox.com/t/recommended-for-you-algorithm-improvements-that-better-value-long-term-retention/4684575)
- Roblox's newsroom framing of the June 2026 change, quoted by Dubit: "overvaluing short-term engagement could disproportionately favour games that win attention with exciting thumbnails." — [Dubit, Sep 2026](https://dubit.io/library/what-makes-a-new-roblox-game-take-off)

**Rules on titles, metadata and thumbnails that affect distribution**
- "A custom thumbnail is required for your game to receive impressions from homepage recommendations." — [Creator Hub: Discovery](https://create.roblox.com/docs/production/promotion/discovery)
- "Metadata that implies any type of monetary reward is not prioritized for recommendations." Metadata or thumbnails that don't match the game (their example: a dinosaur thumbnail on a generic obby) reduce both recommendations and search visibility. Games that closely resemble existing titles or visuals are "no longer prioritized for recommendations." — [Creator Hub: Discovery](https://create.roblox.com/docs/production/promotion/discovery)

**Search**
- Roblox says search is moving away from exact-match, title-based relevance toward understanding intent, using semantic search across all supported languages, so a query like "food games" can match games without those words in the title. — [Creator Hub: Discovery](https://create.roblox.com/docs/production/promotion/discovery)
- Roblox handles "over 50 million searches a day." The top searches of 2025 were Brookhaven, **Grow a Garden** and **Steal a Brainrot**, but "Broad searches like 'horror' and 'roleplay' are even more popular." Searches vary by device: horror, escape and obby content on mobile; Build a Plane and Dress to Impress on tablet. (Roblox Replay, Dec 16 2025) — [Roblox Newsroom](https://about.roblox.com/newsroom/2025/12/roblox-replay-decoded-search-style)
- A Roblox staff member (Nov 20, 2025) said search impressions depend on "overall platform engagement" and "query engagement (what people play when they're looking for X)." A drag-racing game reached the first row for "Drag Racing" after it was **renamed to include "Drag Racing,"** and staff said "renaming your game could have allowed users looking at the game tile to understand it and engage more." — [DevForum thread, Sep-Nov 2025](https://devforum.roblox.com/t/searchdiscovery-suppression-despite-strong-performance/3933936)
- A small game named "Obby Duel" reported that it only showed up when the name was searched in quotes, and suspected crowding from keyword spam in the "obby" space. [OLDER, undated thread, likely 2023] — [DevForum](https://devforum.roblox.com/t/my-game-wont-show-up-at-all-when-i-search-it-up/2523450)

**Industry view**
- Dubit (Sep 2026): a new game has about 30 seconds to win a player, "evolution beats revolution" (evolve a popular genre rather than invent one), and the biggest new games ride trend waves: internet culture (brainrot), established genres (tycoon, obby, escape) and hype (social chaos). — [Dubit](https://dubit.io/library/what-makes-a-new-roblox-game-take-off)
- RDC 2025 announced a new discovery surface, "Roblox Moments" (short-form video). Source is an aggregator recap. — [AllThings.How](https://allthings.how/roblox-rdc-2025-10-creator-tools-and-updates-that-matter/)

### Inferences
- The title and the tile mostly affect signal #1 (PTR). Signals #2-#4 (bounce, play days, playtime) depend on the first 60-180 seconds and on retention. A title that sets a wrong expectation can raise PTR but also raise first-play bounce, and since June 2026 both count. **A title should therefore be judged on whether it matches the first minute of play, as well as whether it gets clicks.**
- Because the RFY tile now autoplays real gameplay video (since July 2026), the slide shot (an item flying down and smashing through ×-walls) is arguably the strongest "thumbnail" this game has. The title's job is to name what that video shows.
- For a new game, search mostly matters in two cases: (a) players who saw the game on TikTok or YouTube and type its name, which needs a short, spellable, distinctive name; and (b) genre queries such as "rng", "tycoon" or "obby", where ranking follows query engagement. The Drag Racing case shows that putting the genre or action word in the title can move search ranking. That is one anecdote, not a general rule.
- Ads and curation (Standout Games) can bootstrap a game, but ad-acquired players don't count toward RFY signals. A distinctive mechanic like distance-based pay with multiplier walls is the kind of novelty the curated sort says it looks for.

### Gaps
- Roblox publishes no weighting for title or icon as a factor separate from PTR, and no click-through data for title text alone.
- I found no official cold-start or grace-period rules for brand-new games under the 28-day window. Commenters asked and got no answer.
- I found no official deep dive on search ranking. The Mar 2026 Home post says "deep dives on Search will come later."
- I did not verify the Jun 2026 newsroom post directly. The clickbait quote comes from Dubit's citation of it.

---

## Q2. Which naming patterns dominate recent hits, and why did "[Verb] a [Noun]" take over?

### Takeaway
The biggest 2025 hits (Grow a Garden, Steal a Brainrot) and their imitators use very short titles in the imperative "[Verb] a [Noun]" form. Each states the action and the object in two or three words. The press notes the brevity and the fact that the action is literal, but **I found no rigorous published analysis of why the format took over.** The explanation below is my inference. Live top games also routinely wrap the stable core name in changing tags and emojis, for example "[UPD] Fish It! 🐟".

### Cited Findings
- Grow a Garden reached a peak of about 22.3M CCU (Aug 23 2025) and Steal a Brainrot is the only Roblox game reported above 25M CCU. "Steal an Egg" (a derivative name) peaked at 14.25M CCU, and 99 Nights in the Forest at 14.2M CCU with 26B visits (Apr 2026). — [Wikipedia: List of Roblox games](https://en.wikipedia.org/wiki/List_of_Roblox_games); [Wikipedia: Steal a Brainrot](https://en.wikipedia.org/wiki/Steal_a_Brainrot); [Wikipedia: Grow a Garden](https://en.wikipedia.org/wiki/Grow_a_Garden)
- Screen Rant: Dress To Impress, Grow A Garden and Steal A Brainrot "have virtually nothing in common beyond their short and snappy titles." — [Screen Rant](https://screenrant.com/roblox-steal-brainrot-fad-explanation/)
- GamesRadar: Steal a Brainrot riffs on both Grow a Garden's **name** and its luck mechanics. — [GamesRadar](https://www.gamesradar.com/games/mmo/with-21-million-concurrent-players-roblox-hit-grow-a-garden-is-bigger-than-half-of-steam-combined-but-players-are-already-flooding-another-far-weirder-competitor/)
- AP (Jul 2025): Grow a Garden is "about as simple as its title": plant, harvest, sell, trade, steal. — [AP via Boston Globe](https://www.bostonglobe.com/2025/07/30/wires/roblox-grow-a-garden-teenager/)
- Plants vs Brainrots combined Grow a Garden's loop, Steal a Brainrot's meme culture and Plants vs Zombies' tower defense, reaching about 9M CCU. — [MaxPower Gaming](https://www.maxpowergaming.co/post/roblox-s-latest-breakout-game-is-plants-vs-brainrots)
- Fish It! (launched Oct 2024 per tracker) has an all-time peak of about 2.7M CCU per RoWatcher. Another RoWatcher page says 1.4M, so the figure is unresolved. Its live title has cycled through "[UPD🕹️] Fish It! 🐟", "[15 MINS] Fish It! 🐟", "[3 HRS] Fish It! 🐟" and "[NOW] Fish It! 🐟", which are update countdown tags around a stable core name. — [RoWatcher](https://rowatcher.com/games/6701277882); [RoWatcher variant](https://rowatcher.com/games/6701277882/3-hrs-fish-it); [RoWatcher variant](https://rowatcher.com/games/6701277882/now-fish-it)
- Grow a Garden put a green-bean emoji in its title for an update, and it did not render in the Roblox app (bug report). — [DevForum: Limited support for certain Unicode emojis](https://devforum.roblox.com/t/limited-support-for-certain-unicode-emojis/3895754)
- "+1 [X] Every Second" and "Roblox but every second you get +1 Walk Speed" titles are described as "flooding the platform." The source is AI-generated and weak. Individual results vary a lot: one "+1 Head Size Every Second" listing peaked at 2 concurrent players. — [gist.ly summary (low quality)](https://gist.ly/youtube-summarizer/roblox-games-taking-over-the-craze-explained); [RoWatcher](https://rowatcher.com/games/6025404033/1-head-size-every-second)
- 2026 roundups list "Escape Tsunami For Brainrots!" as a current top game. Its title combines a verb, a reward noun and a trend word. The roundups' figures are inconsistent and come from fan or affiliate sites. — [Tech2Geek 2026 list](https://www.tech2geek.net/top-10-most-popular-roblox-games-in-2026-ranked/); [Cubix 2026 list](https://www.cubix.co/blog/top-10-most-popular-roblox-games/)
- Industry view: the biggest new games ride trend waves (internet culture, established genres, hype), and players look for new variations once a genre is hot. — [Dubit, Sep 2026](https://dubit.io/library/what-makes-a-new-roblox-game-take-off)

### Inferences
Why "[Verb] a [Noun]" likely works. This is my analysis, not sourced:
1. **It answers "what do I do?" in about one second.** The verb is the core loop and the noun is the thing you collect. That fits Dubit's 30-second rule and RFY's PTR and bounce signals.
2. **It reads like an instruction**, so it doubles as a call to action on the tile.
3. **It is easy to say and to search after seeing the game on TikTok or YouTube.** Two of the top three searches of 2025 were these titles.
4. **It is easy to riff on.** Steal a Brainrot riffed on Grow a Garden, and Steal an Egg followed. The riffing spreads the format and makes the pattern itself feel like a genre signal to kids.
5. **The noun carries the fantasy and the art direction** (garden, brainrot, egg). Fish It!, Dig It and Build a Plane follow the same "single literal action" logic.
- Other patterns in use: "[X] RNG" (genre anchor for roll games), "[X] Simulator" or "[X] Tycoon" (older genre anchors that still help skimming and search), "+1 [X] Every Second" (a mechanic as the title; very crowded and hit-or-miss), and "Escape/Survive [threat] for [reward]".
- Practical norm among top games: a **stable core name, plus a changing bracket tag or emoji** for updates and countdowns.

### Gaps
- I found no Naavik, Deconstructor of Fun or GDC analysis of title formats on Roblox, and no CTR data comparing title formats.
- I could not verify "Dig It" and only partly verified "Fish It!" (via a tracker). I found no reliable 2025-2026 data on "[X] RNG" title performance as a class.

---

## Q3. What do experienced developers and Roblox staff advise about titles: describing the core action, specific versus broad, trademark or collision concerns, renaming after launch, and update tags or emojis?

### Takeaway
Roblox's official guidance favors accurate, specific, consistent and uncluttered titles, with no keyword spam, no monetary-reward implications and no lookalikes of existing games. In practice, top games add update tags and emojis around a stable core name. Renaming to add a descriptive keyword helped at least one game's search ranking. Copycat naming now carries real risk: Roblox deprioritizes it and the Steal a Brainrot developers have filed lawsuits.

### Cited Findings
- [OLDER: Sep 10 2020] Roblox Search & Discovery PSA: "keep the title of your game consistent!", "Maintaining a consistent brand is important for player retention and growth", and "Excessively decorative or distracting titles can also be harmful for retention." It also says "Do not spam the title with keywords; doing so may result in demotion." On descriptions: "The first sentence is very important as it may be displayed in search," and "Be sure to use keywords!" On icons: "The Game Icon is one of the most important factors in getting your game noticed," and "Misleading icons are destructive for retention." — [DevForum PSA](https://devforum.roblox.com/t/psa-best-practices-for-game-metadata/764558)
- 2026 Creator Hub: accurate metadata with no irrelevant keywords. Reward-implying metadata is "not prioritized for recommendations," and games resembling existing titles or visuals are "no longer prioritized for recommendations." Originality is encouraged, as is adding "your own spin" to trends. — [Creator Hub: Discovery](https://create.roblox.com/docs/production/promotion/discovery)
- Renaming: staff linked a rename that added the descriptive keyword ("Street Outlaws **Drag Racing**") with reaching the first search row, and suggested it helped players "understand" the tile (Nov 2025). — [DevForum](https://devforum.roblox.com/t/searchdiscovery-suppression-despite-strong-performance/3933936)
- Community tutorial [OLDER, pre-2025]: keep the title clean and use tags as little as possible. "UPDATE [number]" in titles and icons frustrates players. — [DevForum tutorial](https://devforum.roblox.com/t/naming-your-game-and-presenting-it-to-the-public/1189366)
- Community advice [OLDER, pre-2025]: avoid names that resemble another game, avoid obscure spellings, keep it short, check whether the name is taken by searching Roblox, and ask several people. Another dev notes that on Roblox the first impression is name plus icon, not the description. — [DevForum: Advice on naming a game](https://devforum.roblox.com/t/advice-on-naming-a-game/1989821)
- Low-authority guide: 2-4 words, legible at thumbnail size, and one genre "anchor word" (obby, tycoon, RP, survival, simulator) does "a lot of work for players skimming"; match tone (cozy, competitive, spooky, comedic). — [The Story Shack name generator page](https://thestoryshack.com/tools/roblox-game-name-generator/)
- Collisions and legal: since Nov 2025, the Steal a Brainrot developers have filed "at least four lawsuits against alleged imposters" (Bloomberg, Mar 24 2026). Viral games are routinely cloned "often using the same name" (Plagiarism Today, Sep 17 2026). — [Bloomberg](https://www.bloomberg.com/news/articles/2026-03-24/roblox-s-hit-game-steal-a-brainrot-battles-its-many-imitators); [Plagiarism Today](https://www.plagiarismtoday.com/2026/09/17/the-attack-of-the-roblox-clones/)
- Tags and emojis in practice: Fish It! cycles "[UPD]", "[15 MINS]", "[3 HRS]" and "[NOW]" prefixes plus a 🐟. Grow a Garden used an emoji that failed to render. — [RoWatcher](https://rowatcher.com/games/6701277882); [DevForum emoji bug](https://devforum.roblox.com/t/limited-support-for-certain-unicode-emojis/3895754)

### Inferences
- **Pick the core name carefully once, then decorate around it.** Changing the core words resets recognition for players who search by name, which matters if TikTok or YouTube is the growth channel. Adding a clarifying keyword (the Drag Racing case) is the low-risk kind of rename.
- Update tags and emojis are standard among top games despite the 2020 advice. Use them sparingly (one tag, one emoji). Check that the emoji renders on mobile.
- **Trend-borrowing in the title is now riskier than in 2025**: it gets deprioritized as a lookalike, and big IP holders on the platform are suing. Borrowing a trend *word* in the description or tags is safer than copying a hit's *title structure plus noun*.
- **Item-name flag (not researched here):** one of the game's items is called "Lightsaber," which is widely understood to be a Lucasfilm/Disney trademark. Showing it in a title, icon or thumbnail could invite moderation or IP trouble. Consider a generic name ("Laser Sword", "Plasma Blade"). Verify before launch.

### Gaps
- I found no measured data on the traffic effect of renames, and no current (2025-2026) Roblox statement on "[UPDATE]" tags or emojis in titles.
- I did not search Roblox directly for existing "Slide ..." or "... Everything" titles. The developer should search Roblox for "slide", "slide everything" and "slide rng" and check the top results for collisions.

---

## Q4. How do players phrase searches for this kind of game (slide, drop, launch, roll, RNG, tycoon, brainrot)? Is there data on Roblox search terms or autocomplete?

### Takeaway
Public data is thin. Roblox's own 2025 review shows players mostly search either **hit game names** or **broad genre or vibe words** ("horror", "roleplay"). Roblox says its search now matches intent semantically. I found no public keyword or autocomplete data for "slide", "drop", "launch", "roll", "RNG" or "tycoon".

### Cited Findings
- Over 50M searches a day. The top 2025 searches were Brookhaven, Grow a Garden, Steal a Brainrot, Blue Lock: Rivals, 99 Nights in the Forest, Murder Mystery 2 and RIVALS, with The Forge rising. Broad terms like "horror" and "roleplay" are "even more popular." Trending queries included "67", KPop Demon Hunters, "team green bean", "admin abuse" and "wall hop". Mobile searches lean toward horror, escape and obby. The post does **not** list "RNG", "tycoon" or "simulator." — [Roblox Newsroom, Dec 16 2025](https://about.roblox.com/newsroom/2025/12/roblox-replay-decoded-search-style)
- A Japanese summary of the same report says players increasingly search by playstyle and world rather than by experience name. — [MoguraVR (Japanese)](https://www.moguravr.com/?p=285654)
- Semantic search lets natural-language queries like "food games" match. — [Creator Hub: Discovery](https://create.roblox.com/docs/production/promotion/discovery)
- Search ranking for a query follows "what people play when they're looking for X." — [DevForum staff reply, Nov 2025](https://devforum.roblox.com/t/searchdiscovery-suppression-despite-strong-performance/3933936)

### Inferences
- Likely query families for this game: genre ("rng", "tycoon", "simulator", "incremental"), action ("slide", "drop", "launch"), and trend ("brainrot"). "Everything" is not a word anyone types to find a game.
- "Slide" is probably a contested query, likely full of slide or sled obbies and water-slide games (unverified). A slide game competes for the click with games where the *player* slides.
- With semantic search, the description's first sentence and the in-game content probably matter more than exact title words. But a genre or action word in the title still helps the tile be understood (the Drag Racing case).

### Gaps
- I found no public Roblox autocomplete, keyword-volume or search-term dataset. RoMonitor-style trackers did not surface search data in my searches. The developer can type candidate words into Roblox search to see autocomplete and current competitors.

---

## Q5. What evidence exists on thumbnail and icon A/B testing (thumbnail personalization), and what wins?

### Takeaway
Roblox's built-in thumbnail personalization (2-5 thumbnails, per-segment winners) gives an average **+8.5% to +12% lift in qualified play-through** (up to +50-56%) according to Roblox's own data. Staff advice is to test *genuinely different* concepts, refresh with each update, and avoid clickbait. **Roblox has published no data showing that faces, big numbers or exaggerated scale win.** Those are community and YouTube conventions. From mid-2026, real gameplay video on the RFY tile is also a major lever.

### Cited Findings
- Mechanics: personalization starts once 2 or more thumbnails are active (up to 5). Each thumbnail is shown to random users, and then the system "gives more impressions to the winning thumbnail for each group." The winner is "the thumbnail with the highest play through rate." Thumbnails are 16:9 at 1920×1080, and essential text should stay away from the bottom edge, where player count is overlaid. — [Creator Hub: Thumbnails](https://create.roblox.com/docs/production/publishing/thumbnails)
- Lift: "an average increase of +8.5% in their qualified play through rate," and "Some games had an increase of +50%." — [Creator Hub: Thumbnails](https://create.roblox.com/docs/production/publishing/thumbnails)
- Feb 13, 2025 staff tips: more than 8,000 experiences adopted it, with an average +12% relative qPTR lift and up to +56%. Tips: (1) don't restart tests within 7 days; (2) keep up to 5 active, since "testing more thumbnails can lead to greater gains"; (3) show new content or features and avoid clickbait, which can trigger low-quality warnings; (4) don't test near-identical thumbnails, and vary the gameplay shown, the characters, the environment or the player motivation (competition, creativity, social); (5) expect qPTR dips after recommendation surges. Segments reported are age groups, and gender was being tested internally. — [DevForum, Feb 13 2025](https://devforum.roblox.com/t/5-tips-from-roblox-staff-to-get-the-most-out-of-thumbnail-personalization/3471689)
- One developer in that thread had qPTR under 1%, and said a better thumbnail brought "a large boost in home recommendations." — [same thread](https://devforum.roblox.com/t/5-tips-from-roblox-staff-to-get-the-most-out-of-thumbnail-personalization/3471689)
- July 2025: personalization "remembers existing winning thumbnails," reported as +0.19% qPTR and 21% fewer impressions to non-winners. This comes from a search snippet of the announcement; I did not fetch the full thread. — [DevForum, Jul 2025](https://devforum.roblox.com/t/thumbnail-personalization-now-remembers-your-existing-winning-thumbnails/3793665)
- June 2026: Roblox is testing moving personalization from qPTR to PTR. — [DevForum, Jun 15 2026](https://devforum.roblox.com/t/recommended-for-you-algorithm-improvements-that-better-value-long-term-retention/4684575)
- Rules: "Overlay text sparingly and only to describe gameplay contexts." Do not include "an advertisement, promotion, or subjective claim," and do not show mechanics or UI the game doesn't have. Video thumbnails must be authentic. — [Creator Hub: Thumbnails](https://create.roblox.com/docs/production/publishing/thumbnails)
- Gameplay videos autoplay on RFY tiles (Jul 29 2026), and Standout Games primarily shows video previews. — [DevForum: Home 2026](https://devforum.roblox.com/t/how-we-are-improving-home-this-year/4502571)

### Inferences
Concrete concepts worth testing for this game (my analysis, not tested):
- (A) **Payoff shot**: a Diamond or Hyperlaser smashing through a "×10" wall with a big pay number.
- (B) **Absurd item shot**: a Catfish or Bread zooming down the slide.
- (C) **Rarity shot**: a roll reveal with odds text such as "1 in 10,000".
- (D) **Collection shot**: a row of slots full of glowing items.

These cover different motivations (payoff, comedy, gambling, collection), as the staff tip recommends. Multiplier numbers shown are real in-game UI, so they fit the "in-game UI text" allowance.
- The video tile should show the single most satisfying 3-5 seconds: the item crossing multiplier walls with the stud counter climbing.

### Gaps
- There are no Roblox-published A/B results on faces, character reactions, big numbers, exaggerated scale or text overlays. Claims that these win come from YouTube-thumbnail practice and are unverified for Roblox.
- There is no published icon A/B tool or data. Icons are not part of thumbnail personalization per the docs.
- The search summary mentioned a developer complaint that a higher-CTR thumbnail produced less playtime and Robux. I could not confirm which thread it was in, so it is not cited.

---

## Q6. How does "Slide Everything" do on clarity, the vagueness of "everything", distinctiveness and search fit, and what alternatives would score better?

### Takeaway
All of this section is my analysis, built on the sourced points above. "Slide Everything" is short, verb-led, ownable and future-proof. However, it names neither the payoff (distance, money, multipliers) nor the RNG roll, and it doesn't make clear *who* slides. "Everything" is abstract (no picture comes to mind), unsearchable, and promises a breadth that 12 items can't deliver. Stronger framings either (a) keep a verb-led two-to-three-word title but use a concrete noun or the payoff, or (b) add a genre anchor (RNG or tycoon) that matches how players search.

### Cited Findings
These are the sourced basis for the rubric:
- PTR (does the tile get the click?) is the #1 RFY signal, and first-play bounce is #2. — [Creator Hub: Discovery](https://create.roblox.com/docs/production/promotion/discovery)
- Roblox moved to 28-day signals to stop over-rewarding attention-grabbing thumbnails. — [Dubit quoting Roblox, Sep 2026](https://dubit.io/library/what-makes-a-new-roblox-game-take-off); [DevForum, Jun 15 2026](https://devforum.roblox.com/t/recommended-for-you-algorithm-improvements-that-better-value-long-term-retention/4684575)
- Mismatched metadata reduces recommendations and search. Lookalike titles are deprioritized. Reward-implying metadata is not prioritized. — [Creator Hub: Discovery](https://create.roblox.com/docs/production/promotion/discovery)
- Adding the descriptive keyword to a title helped search ranking in one staff-confirmed case. — [DevForum](https://devforum.roblox.com/t/searchdiscovery-suppression-despite-strong-performance/3933936)
- Players search hit names and broad genre words most. — [Roblox Newsroom, Dec 2025](https://about.roblox.com/newsroom/2025/12/roblox-replay-decoded-search-style)
- The top hits use short, literal "[Verb] a [Noun]" titles. — [Screen Rant](https://screenrant.com/roblox-steal-brainrot-fad-explanation/); [AP via Boston Globe](https://www.bostonglobe.com/2025/07/30/wires/roblox-grow-a-garden-teenager/)
- New games have about 30 seconds to win a player. "Evolution beats revolution." — [Dubit](https://dubit.io/library/what-makes-a-new-roblox-game-take-off)

### Inferences

**Strengths of "Slide Everything" (analysis)**
- It starts with a verb in the imperative, the same grammar as Grow a Garden and Steal a Brainrot.
- It is two words, so it stays legible at tile size and is easy to say.
- "Everything" has some absurdist meme energy, since you can slide a catfish, a slice of bread, even a slide.
- It is future-proof: any new item fits.
- It is probably distinctive, with low collision risk (unverified).

**Weaknesses (analysis)**
1. **Ambiguous subject.** On Roblox, "slide" usually means *your avatar* slides (obbies, slide-down games). Nothing says *items* slide.
2. **"Everything" is abstract.** You can't draw it on an icon, and it gives no concrete noun to anchor the fantasy, unlike garden, brainrot or egg.
3. **No payoff signal.** The real hook is that farther equals richer, with ×-walls multiplying the pay. Neither the distance nor the multipliers nor the money appears.
4. **Half the loop is hidden.** The RNG roll (rarity, odds) is the retention engine and the most searched-for genre signal, and the title omits it.
5. **It over-promises.** "Everything" against 12 items risks a mismatch in the first minute, which feeds bounce rate, now signal #2.
6. **Weak search fit.** No one searches "everything". "Slide" is contested, and there is no genre anchor such as RNG, tycoon or simulator.

**Scoring rubric (analysis)**
Score each criterion 1-5 and multiply by its weight. The maximum is 85. Weights reflect the RFY signal order: click first, then no bounce.

| # | Criterion | Weight | What a 5 looks like |
|---|---|---|---|
| 1 | Action clarity: a 9-year-old knows what they *do* in 1 second | ×3 | "Grow a Garden" |
| 2 | Expectation match: the first 60 s of play matches the title (bounce risk) | ×3 | Title literally describes the opening loop |
| 3 | Concrete picture: the title can be drawn on the icon or thumbnail | ×2 | Names a specific object |
| 4 | Payoff or fantasy signal: hints at progress, number-go-up, rarity | ×2 | "for Treasure", "RNG", "×100" |
| 5 | Search fit: has a word players type (genre anchor or core action) | ×2 | Contains "RNG", "Tycoon" or "Obby" |
| 6 | Distinctiveness: ownable, not a lookalike, no IP or lawsuit risk | ×2 | Unique phrase, no hit's structure plus noun copied |
| 7 | Brevity and legibility (2-4 words) | ×1 | 2-3 short words |
| 8 | Sayability and meme-ability: kids can shout it and clip it | ×1 | Rhythmic, funny, imperative |
| 9 | Extensibility: survives new items and updates | ×1 | Doesn't lock to one item |

**"Slide Everything":** clarity 3 (×3=9), expectation 2 (6), concrete 2 (4), payoff 1 (2), search 2 (4), distinct 4 (8), brevity 5, say 3, extend 5 → **46/85**.

**Alternative framings: title plus one-line hook (analysis; scores are rough)**

| Title | One-line hook | Why it could score better | Risks | ~Score |
|---|---|---|---|---|
| **Roll & Slide** | "Roll rare items, send them down the slide. The farther they go, the richer you get." | Names both halves of the loop, with "roll" hinting at RNG. Short, rhythmic. | Still no concrete noun. Possible name collisions (unverified). | ~60 |
| **Slide RNG** (or **Slide Item RNG**) | "Roll for 1-in-a-million items, then slide them through ×10 walls." | "RNG" is a genre anchor players type, and it sets the expectation of roll-for-rarity. | Generic. "RNG" titles are crowded. Less memorable as a brand. | ~58 |
| **Send It Down the Slide** | "Roll an item. Send it. Smash the multipliers." | The meme phrase "send it" makes the action and the item-as-object unmistakable, and it's very sayable. | 5 words, long for a tile. Weak search anchor. | ~60 |
| **How Far Will It Slide?** | "Every stud pays. Every wall multiplies. How far can your Diamond go?" | A question hook that names the distance payoff and invites a "one more try" curiosity click. | Question titles are uncommon on Roblox (untested). Weak search fit. | ~57 |
| **Slide a Catfish** (or another funny hero item) | "Start with a catfish. End with a Hyperlaser." | Concrete, absurd, meme-able noun in the proven [Verb] a [Noun] grammar, without copying a specific hit. | Locks the brand to one item. Could read as a joke game. Watch for the lookalike deprioritization. | ~59 |
| **Multiplier Slide** | "Drop items through ×2, ×5, ×100 walls. Every stud pays." | Names the unique mechanic, the multiplier walls, which also fits "Standout Games" novelty. Concrete for the thumbnail. | Less of a verb or imperative. Bland. | ~55 |
| **Slide Tycoon** (or **Mega Slide Tycoon**) | "Fill your slots, slide your loot, build the longest slide." | "Tycoon" is a well-known anchor that matches the slot and passive-income half. | Crowded, generic, low distinctiveness. Over-promises building. | ~54 |
| **Slide Everything** with a fixed hook (keep the name) | Description line 1: "Roll rare items, slide them through multiplier walls, and get paid for every stud." Thumbnail shows an item smashing a ×10 wall. | Keeps the brand and future-proofing. The tile and description fix the clarity problem, since semantic search reads the description. | Doesn't fix search fit or the "who slides?" ambiguity in the title itself. | ~50-52 |

Notes on the alternatives:
- **Avoid** riding a hit's title structure plus its noun, such as "Slide a Brainrot." Roblox deprioritizes lookalikes, and the Steal a Brainrot owners have sued imitators. If the game leans into brainrot, put it in the item roster and description rather than the title.
- **Avoid reward language** such as "Slide for Robux" or "free money", which Roblox does not prioritize.
- **Practical validation** (Roblox has no built-in title A/B test that I found):
  1. Run thumbnail personalization with 4-5 genuinely different concepts (payoff, absurd item, rarity, collection).
  2. Test 2-3 title candidates off-platform as short-form video hooks or by asking target-age playtesters "what do you do in this game?".
  3. Commit to one core name before any marketing push, then use one "[UPD]" tag or emoji for updates.
- **The developer's doubt about "everything" is well-founded** from a discovery standpoint. The problem is less the word itself and more that the title has no concrete object, no payoff and no genre anchor. Any replacement should add at least two of those three.

### Gaps
- None of the alternative scores are empirically tested. They are judgment calls on the rubric.
- I did not check name availability or collisions on Roblox for any candidate.
- I found no data on how question titles or 4-5-word titles perform compared with 2-word titles on Roblox.
