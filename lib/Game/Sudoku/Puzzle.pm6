unit class Game::Sudoku::Puzzle;
use v6;

subset CellNumber of Int where 1 <= * <= 9;
subset CellRow of Str where /^ <[A .. I]> $/;
subset CellColumn of Int where 1 <= * <= 9;
subset CellName of Str where /^ <[A .. I]> <[1 .. 9]> $/;
subset BoxNumber of Int where 1 <= * <= 9;

our constant @ALL-CELL-ROWS = 'A' .. 'I';
our constant @ALL-CELL-COLUMNS = 1 .. 9;
our constant @ALL-BOX-NAMES = 1 .. 9;
our constant @ALL-CELL-NUMBERS = 1 .. 9;
our constant @ALL-CELL-NAMES = @ALL-CELL-ROWS X~ @ALL-CELL-COLUMNS;
my constant %CELL-INDEX = %(@ALL-CELL-NAMES.kv.reverse);

# TODO When multi-dimensional, shaped arrays get implemented, make this awesome:
# has CellNumber @.board{'A' .. 'I'; 1 .. 9};
# has SetHash @.candidates{'A' .. 'I'; 1 .. 9};
# Much of the infrastructure for looking up cells and such can be fixed once
# multi-dimension arrays and shaping are full implemented.

has CellNumber @.board[81];
has SetHash @.candidates[81];

multi method cell-number(CellName:D $name) is rw returns CellNumber {
    @.board[ %CELL-INDEX{ $name } ];
}

multi method cell-number(CellName:D $name, CellNumber $value) {
    @.board[ %CELL-INDEX{ $name } ] = $value;
    Nil;
}

method clear-cell(CellName:D $name) {
    @.board[ %CELL-INDEX{ $name } ] = Nil;
    Nil;
}

multi method cell-candidates(CellName:D $name) is rw returns SetHash {
    @.candidates[ %CELL-INDEX{ $name } ];
}

multi method cell-candidates(CellName:D $name, SetHash:D $candidates) {
    @.candidates[ %CELL-INDEX{ $name } ] = $candidates;
    Nil;
}

method add-candidate(CellName:D $name, CellNumber:D $value) {
    @.candidates[ %CELL-INDEX{ $name } ]{ $value } = True;
    Nil;
}

method remove-candidate(CellName:D $name, CellNumber:D $value) {
    @.candidates[ %CELL-INDEX{ $name } ]{ $value } = False;
    Nil;
}

my sub row-names(CellRow $r) {
    my $i = $r.ord - ord('A');
    my @r = $i * 9 ... ($i + 1) * 9 - 1;
    @ALL-CELL-NAMES[@r];
}

my multi sub column-names(CellColumn $c) {
    my $i = $c - 1;
    @ALL-CELL-NAMES[$i, $i + 9 ... $i + 72];
}

my multi sub column-names(Str $c) { column-names($c.Int) }

my sub box-names(BoxNumber $b) {
    my $i = $b - 1;
    my $origin = ($i mod 3) * 3 + ($i div 3) * 27;
    flat @ALL-CELL-NAMES[
        $origin +  0 .. $origin +  2,
        $origin +  9 .. $origin + 11,
        $origin + 18 .. $origin + 20,
    ];
}

my multi sub box-names-for(CellRow $row, CellColumn $col) {
    my $r = $row.ord - ord('A');
    my $c = $col - 1;
    box-names(1 + ($r div 3) * 3 + $c div 3);
}

my multi sub box-names-for(CellRow $row, Str $col) {
    box-names-for($row, $col.Int);
}

method initialize-candidates() {
    for @.candidates -> $p is rw { $p = @ALL-CELL-NUMBERS.SetHash }
    self.revise-candidates;
    Nil
}

method revise-candidates() {
    for @.board.kv -> $i, $val {
        $val or next;

        my $name = @ALL-CELL-NAMES[$i];
        my @impact-cells =
            |row-names($name.comb[0]),
            |column-names($name.comb[1]),
            |box-names-for(|$name.comb),
            ;

        for @impact-cells -> $cell {
            self.remove-candidate($cell, $val);
        }

        self.cell-candidates($name, ($val).SetHash);
    }

    Nil
}

method count-all-candidates() {
    (0, |@.candidates).reduce({ $^a + $^b.elems });
}

method infer-naked-candidate() returns Bool {
    for @ALL-CELL-NAMES Z @.candidates -> ($name, $candidate) {
        #dd $name, $candidate;
        $candidate.elems == 1 or next;
        without self.cell-number($name) {
            self.cell-number($name, my $val = $candidate.pick);
            note "[$name, $val]: Naked Candidate";
            return True;
        }
    }
    False;
}

our @ALL-NINES = [
     |@ALL-CELL-ROWS.map(&row-names),
     |@ALL-CELL-COLUMNS.map(&column-names),
     |@ALL-BOX-NAMES.map(&box-names),
];

method by-nine-cells() {
    @ALL-NINES.map(-> $cells { @$cells Z @.candidates[ %CELL-INDEX{ @$cells } ] });
}

method infer-naked-single() returns Bool {
    for self.by-nine-cells -> @cells {
        my $counts = bag(@cells.map({ .[1].keys }));
        for $counts.kv -> $k, $v {
            next unless $v == 1;
            for @cells -> ($name, $candidates) {
                next unless $candidates ∋ $k;
                without self.cell-number($name) {
                    self.cell-number($name, $k);
                    self.cell-candidates($name, ($k).SetHash);
                    note "[$name, $k]: Naked Single";
                    return True;
                }
            }
        }
    }
    False;
}

method infer-naked-pair() returns Bool {
    for self.by-nine-cells -> @cells {
        for @cells.combinations(2) -> (($name1, $c1), ($name2, $c2)) {
            for @ALL-CELL-NUMBERS.combinations(2) -> ($val1, $val2) {
                next unless $val1 < $val2;

                if $c1.elems == 2 && $c2.elems == 2
                        && $c1 ∋ $val1 && $c1 ∋ $val2 
                        && $c2 ∋ $val1 && $c2 ∋ $val2 {

                    my $changed = False;
                    for @cells.map({ .[0] }) -> $a-name {
                        next if $a-name ~~ any($name1, $name2);
                        next unless self.cell-candidates($a-name) ∩ set($val1, $val2);

                        self.remove-candidate($a-name, $val1);
                        self.remove-candidate($a-name, $val2);
                        $changed = True;
                    }
                    
                    if $changed {
                        note "[$name1/$name2, $val1/$val2]: Naked Pair";
                        return True;
                    }
                }
            }
        }
    }
    False;
}


method is-plausible() returns Bool {
    for self.by-nine-cells -> $cells {
        my $counts = bag($cells.map({ .keys }));
        for $counts.kv -> $number, $count {
            return False if $count > 1;
        }
    }
    True;
}

method is-complete() returns Bool {
    return False unless self.is-plausible();
    @.board.grep({ .defined }) == 81
}

method show-board(IO::Handle $fh = $*OUT) {
    for @.board.kv -> $i, $val {
        $fh.print($val.defined ?? $val !! '.');
        $fh.print("\n") if ($i+1) %% 9;
    }
    Nil
}

method show-possible(IO::Handle $fh = $*OUT) {
    for cross(@ALL-CELL-ROWS, 0..2, @ALL-CELL-COLUMNS, 0..2) -> ($row, $prow, $col, $pcol) {
        my $set = self.cell-candidates($row ~ $col);
        my $val = $prow * 3 + $pcol + 1;
        $fh.print("│") if $pcol == 0 && $col != 1;
        $fh.print($set ∋ $val ?? $val !! ' ');
        if $col == 9 && $pcol == 2 {
            $fh.print("\n");
            $fh.say("───┼" x 8 ~ "───") if $prow == 2 && $row ne 'I';
        }
    }
    Nil
}

method solve() {
    self.initialize-candidates;
    #    self.show-possible;
    loop {
        last unless False
            or self.infer-naked-candidate
            or self.infer-naked-single
            or self.infer-naked-pair
            ;
        self.revise-candidates;

        #        say "#" x 150;
        #        self.show-possible;
    }
}
