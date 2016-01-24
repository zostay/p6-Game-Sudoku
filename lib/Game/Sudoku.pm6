unit class Game::Sudoku;
use v6;

use Game::Sudoku::Puzzle;

multi method load-puzzle(Str $path) { samewith($path.IO) }
multi method load-puzzle(IO::Path $path) returns Game::Sudoku::Puzzle {
    my $puzzle = Game::Sudoku::Puzzle.new;

    for $path.lines.kv -> $r, $line {
        for $line.comb(/./).kv -> $c, $ch {
            so $ch ~~ /\d/ or next;

            my $val = $ch.Int;
            die "$path contains illegal puzzle value '$ch' in position ($r, $c)"
                unless 1 <= $val <= 9;

            my $i = @Game::Sudoku::Puzzle::ALL-CELL-NAMES[$r * 9 + $c];
            $puzzle.cell-number($i, $val);
        }
    }

    $puzzle;
}

multi method save-puzzle(Str $path, Game::Sudoku::Puzzle $puzzle) { samewith($path.IO, $puzzle) }
multi method save-puzzle(
    IO::Path $path,
    Game::Sudoku::Puzzle $puzzle,
) {
    my $fh = $path.open(:w);
    $puzzle.show($fh);
}
