unit class Game::Sudoku::Puzzle;
use v6;

has Int @.board[9;9] where 1 <= * <= 9;
has SetHash @.possibles[9;9];

method !this-square-coords($r, $c) {
    my $row-range = $r div 3 * 3 .. $r div 3 * 3 + 2;
    my $col-range = $c div 3 * 3 .. $c div 3 * 3 + 2;
    $row-range, $col-range
}

method !the-square-coords($i) {
     my $r = $i div 3 * 3;
     my $c = $i mod 3 * 3;
     self!this-square-coords($r, $c);
}

method initialize-possibles() {
    for @.possibles -> $p is rw { $p = [1..9].SetHash }
    self.revise-possibles;
    Nil
}

method revise-possibles() {
    for @.board.kv -> ($r, $c), $val {
        $val or next;

        for 0..8 -> $rc {
            @.possibles[$r; $rc]{ $val } = False;
            @.possibles[$rc; $c]{ $val } = False;
        }

        my ($row-range, $col-range) = self!this-square-coords($r, $c);
        for cross(@$row-range, @$col-range) -> ($sr, $sc) {
            @.possibles[$sr; $sc]{ $val } = False;
        }

        @.possibles[$r; $c] = ($val).SetHash;
    }

    Nil
}

method count-possibilities() {
    (0, |@.possibles).reduce({ $^a + $^b.elems });
}

method infer-definite-possibilities() {
    for @.possibles.kv -> ($r, $c), $p {
        $p.elems == 1 or next;
        @.board[$r; $c] = $p.pick;
    }
    Nil
}

method by-nines() {
    my enum Mode <Row Col Squ>;

    ([Row, Col, Squ] X [0..8]).map: -> ($mode, $i) {
        my @n;
        given $mode {
            when Row {
                @n[$_] := @.possibles[$i; $_] for 0..8;
            }
            when Col {
                @n[$_] := @.possibles[$_; $i] for 0..8;
            }
            when Squ {
                my ($row-range, $col-range) = self!the-square-coords($i);
                for @$row-range X @$col-range X 0..8 -> ($r, $c, $j) {
                    @n[$j] := @.possibles[$r;$c];
                }
            }
        }
        @n;
    }
}

method infer-only-possible-place() {
    for self.by-nines -> $nine {
        my $counts = bag($nine.map({ .keys }));
        for $counts.kv -> $k, $v {
            next unless $v == 1;
            for @$nine -> $p is rw {
                next unless $p ∋ $k;
                $p = ($k).SetHash;
            }
        }
    }
}

method infer-doubles-must-be-only() {
    for self.by-nines -> $nine {
        for cross(0..8, 0..8, 1..9, 1..9) -> ($i, $j, $val1, $val2) {
            next unless $j > $i && $val2 > $val1;

            if $nine[$i].elems == 2 && $nine[$j].elems == 2
                    && $nine[$i] ∋ $val1 && $nine[$i] ∋ $val2 
                    && $nine[$j] ∋ $val1 && $nine[$j] ∋ $val2 {

                for 0..8 -> $k {
                    next if $k ~~ any($i, $j);
                    $nine[$k]{ $val1 } = False;
                    $nine[$k]{ $val2 } = False;
                }
            }
        }
        Nil
    }
    Nil
}


method is-plausible() returns Bool {
    my (@rows[9;9], @cols[9;9]);
    for @.board.kv -> ($r, $c), $val {
        $val or next;

        @rows[$r;$val]++;
        @cols[$c;$val]++;
    }

    return False if @rows.grep(* > 1);
    return False if @cols.grep(* > 1);
    True
}

method is-complete() returns Bool {
    return False unless self.is-plausible();
    @.board.grep({ .defined }) == 81
}

method show-board(IO::Handle $fh = $*OUT) {
    for @.board.kv -> ($r, $c), $val {
        $fh.print($val.defined ?? $val !! '.');
        $fh.print("\n") if $c == 8;
    }
    Nil
}

method show-possible(IO::Handle $fh = $*OUT) {
    for cross(0..8, 0..2, 0..8, 0..2) -> ($row, $prow, $col, $pcol) {
        my $set = @.possibles[$row; $col];
        my $val = $prow * 3 + $pcol + 1;
        $fh.print("│") if $pcol == 0 && $col != 0;
        $fh.print($set ∋ $val ?? $val !! ' ');
        if $col == 8 && $pcol == 2 {
            $fh.print("\n");
            $fh.say("───┼" x 8 ~ "───") if $prow == 2 && $row != 8;
        }
    }
    Nil
}
 
method solve() {
    self.initialize-possibles;
    self.show-possible;
    my $count = self.count-possibilities;
    loop {
        self.infer-only-possible-place;
        self.infer-doubles-must-be-only;
        self.infer-definite-possibilities;
        self.revise-possibles;

        say "#" x 150;
        self.show-possible;

        my $new-count = self.count-possibilities;
        last if $new-count == $count;
        $count = $new-count;
    }
}
