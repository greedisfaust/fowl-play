# Poker

Poker is a chicken-themed Three Card Poker table in Fowl Play. One to four players can participate in a round, with each player competing individually against an automated dealer. Players enter an Ante per player through the shared keypad, then choose whether to Fold or Play after receiving three cards. The host manages the deck, player decisions, shared wallet transactions and payouts.

## Rules and feedback

- Uses a fresh, shuffled standard 52-card deck without jokers. Cards are drawn without replacement.
- Each participating player receives three cards. The dealer also receives three cards.
- The first seated player sets the Ante using the shared keypad. The entered amount is the Ante per player. Total Ante is calculated as Ante per player multiplied by the number of participating seats.
- The current configured Ante range is $50–$100 per player.
- The total Ante is deducted from the shared wallet when the round begins. Each player receives an individual Ante record.
- Players privately see their own cards. The dealer's cards remain hidden until all participating players have made their decisions.
- Each player chooses FOLD or PLAY. Folding forfeits the Ante. Playing requires an additional bet equal to the player's Ante.
- A player who cannot afford the Play bet automatically folds.
- Players have 15 seconds to decide. Undecided players automatically fold when the timer expires.
- The dealer qualifies with Queen-high or better.
- Hand rankings, from lowest to highest: high card, pair, flush, straight, three of a kind, straight flush.
- A-2-3 is the lowest straight. Ace is otherwise high.
- If the player beats a qualifying dealer, the Ante and Play each return their stake plus 1:1 winnings.
- If the player loses, both committed bets are lost. A tie returns both stakes.
- If the dealer does not qualify, the Ante pays 1:1 and the Play bet is returned.
- Proposed special bonuses: Straight Flush pays 5× the Ante, and Three of a Kind pays 4× the Ante. Bonuses are additional winnings and require the player to choose Play.
- The table displays player states, cards when permitted, dealer information, countdown and results.

## Implementation

`tables/poker/poker_rules.gd` is a `RefCounted` Three Card Poker model, separate from the table UI, wallet and networking. It handles deck generation, card evaluation, hand comparison, dealer qualification, Ante calculations and individual settlement.

`table.gd` integrates the rules with `TableBase`, player seating, shared keypad input, private card delivery and public table snapshots. The host owns the deck and round state. Each player receives their own cards through a private RPC, while other players receive public snapshots without access to hidden hands.

The host validates the Ante and Play deductions through `GameState.try_spend()`, calculates individual results, credits gross returns and records round outcomes.

The current table implementation uses individual Fold, Play and OK buttons. Removing the individual OK button and making Fold and Play immediately confirm decisions is a planned control change, not yet implemented.

The current implementation also needs further review of day-end settlement, disconnect handling and multiplayer wallet interactions before the feature can be considered fully validated.

## Reproduce checks

Poker-specific deterministic rules, economy, multiplayer and lifecycle tests have not yet been documented here.

Add the actual test command and recorded validation results after the Poker Table test suite has been implemented and executed.

Do not report test counts or successful multiplayer validation until those checks have actually been performed.

## Team Discussion and Pending Decisions

The following points need team review before the Poker Table rules are finalized.

### 1. Betting and Ante
- Is $50–$100 per player a reasonable Ante range?
- Should the Ante range change depending on the number of participating players?
- Is multiplying the Ante by the number of seated players the preferred approach?

### 2. Player Controls
- Should each player have only two buttons: FOLD and PLAY?
- Should pressing either button immediately confirm the decision?
- Should a separate shared DEAL button be used to start the round after Ante confirmation?

### 3. Payouts and Bonuses
- Are the proposed 1:1 payouts balanced?
- Should Straight Flush receive a 5× Ante bonus?
- Should Three of a Kind receive a 4× Ante bonus?
- Should special bonuses still be awarded when the dealer beats the player's hand?

### 4. Dealer Rules
- Should the dealer qualify with Queen-high or better?
- Are the current hand rankings and tie-breaking rules appropriate?

### 5. Multiplayer Behavior
- Should players who disconnect during a round automatically Fold?
- Should the round continue if one or more players disconnect?
- Are the current seat-locking rules appropriate?

### 6. Testing
- Test with 1, 2, 3, and 4 players.
- Test insufficient shared wallet balance.
- Test simultaneous Play decisions and wallet deductions.
- Test player disconnections and day-end settlement.
- Verify that other minigames remain playable during a Poker round.

### Team Feedback
Add suggestions, concerns, and proposed changes before finalizing the rules.
