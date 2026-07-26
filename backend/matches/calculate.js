const WIN_POINTS = 3;
const LOSS_POINTS = 0;

// Determines the winning team for a match. No ties are possible per
// business rules — higher score always wins.
function getWinningTeam(match) {
  return match.score_team1 > match.score_team2 ? 1 : 2;
}

function emptyStats() {
  return {
    wins: 0,
    losses: 0,
    matches_played: 0,
    points_scored: 0,
    points_against: 0,
    bet_matches: 0,
    bet_wins: 0,
  };
}

function ensurePlayer(statsByPlayer, playerId) {
  if (!statsByPlayer[playerId]) {
    statsByPlayer[playerId] = emptyStats();
  }
  return statsByPlayer[playerId];
}

// Computes per-player ranking stats over a list of match records.
// matches: array of Matches table items (already filtered to the desired
// date range and, if applicable, has_bet = true, by the caller).
function calculateRanking(matches) {
  const statsByPlayer = {};

  for (const match of matches) {
    const team1 = [match.player1_team1, match.player2_team1];
    const team2 = [match.player1_team2, match.player2_team2];
    const winningTeam = getWinningTeam(match);

    const team1Won = winningTeam === 1;
    const team1Score = match.score_team1;
    const team2Score = match.score_team2;

    for (const playerId of team1) {
      if (!playerId) continue;
      const stats = ensurePlayer(statsByPlayer, playerId);
      stats.matches_played += 1;
      stats.points_scored += team1Score;
      stats.points_against += team2Score;
      if (team1Won) {
        stats.wins += 1;
      } else {
        stats.losses += 1;
      }
      if (match.has_bet) {
        stats.bet_matches += 1;
        if (team1Won) stats.bet_wins += 1;
      }
    }

    for (const playerId of team2) {
      if (!playerId) continue;
      const stats = ensurePlayer(statsByPlayer, playerId);
      stats.matches_played += 1;
      stats.points_scored += team2Score;
      stats.points_against += team1Score;
      if (!team1Won) {
        stats.wins += 1;
      } else {
        stats.losses += 1;
      }
      if (match.has_bet) {
        stats.bet_matches += 1;
        if (!team1Won) stats.bet_wins += 1;
      }
    }
  }

  return Object.entries(statsByPlayer).map(([playerId, stats]) => {
    const points = stats.wins * WIN_POINTS + stats.losses * LOSS_POINTS;
    const winPct =
      stats.matches_played > 0 ? stats.wins / stats.matches_played : 0;
    const pointsRatio =
      stats.points_against > 0
        ? stats.points_scored / stats.points_against
        : stats.points_scored > 0
          ? Infinity
          : 0;
    const betWinPct =
      stats.bet_matches > 0 ? stats.bet_wins / stats.bet_matches : 0;

    return {
      player_id: playerId,
      wins: stats.wins,
      losses: stats.losses,
      matches_played: stats.matches_played,
      win_pct: winPct,
      points,
      points_scored: stats.points_scored,
      points_against: stats.points_against,
      points_ratio: pointsRatio,
      bet_matches: stats.bet_matches,
      bet_wins: stats.bet_wins,
      bet_win_pct: betWinPct,
    };
  });
}

// sortBy: "points" (default) or "win_pct"
function sortRanking(ranking, sortBy = "points") {
  const key = sortBy === "win_pct" ? "win_pct" : "points";
  return [...ranking].sort((a, b) => b[key] - a[key]);
}

module.exports = { calculateRanking, sortRanking, getWinningTeam };
