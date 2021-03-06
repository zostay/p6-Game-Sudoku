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
# has Set @.candidates{'A' .. 'I'; 1 .. 9};
# Much of the infrastructure for looking up cells and such can be fixed once
# multi-dimension arrays and shaping are full implemented.

has CellNumber @.board[81];
has Set @.candidates[81];

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

multi method cell-candidates(CellName:D $name) is rw returns Set {
    @.candidates[ %CELL-INDEX{ $name } ];
}

multi method cell-candidates(CellName:D $name, Set:D $candidates) {
    @.candidates[ %CELL-INDEX{ $name } ] = $candidates;
    Nil;
}

method add-candidate(CellName:D $name, CellNumber:D $value) {
    self.also-candidates($name, [$value]);
    Nil;
}

method except-candidates(CellName:D $name, @candidates) {
    @.candidates[ %CELL-INDEX{ $name } ] ∖= @candidates;
    Nil
}

method also-candidates(CellName:D $name, @candidates) {
    @.candidates[ %CELL-INDEX{ $name } ] ∪= @candidates;
    Nil
}

method only-candidates(CellName:D $name, @candidates) {
    @.candidates[ %CELL-INDEX{ $name } ] ∩= @candidates;
    Nil
}

method remove-candidate(CellName:D $name, CellNumber:D $value) {
    self.except-candidates($name, [$value]);
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

my multi sub box-names-for(CellName $name) {
    box-names-for(|$name.comb);
}

method initialize-candidates() {
    for @.candidates -> $p is rw { $p = set(@ALL-CELL-NUMBERS) }
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

        self.cell-candidates($name, set($val));
    }

    Nil
}

method count-all-candidates() {
    (0, |@.candidates).reduce({ $^a + $^b.elems });
}

method infer-naked-single() returns Bool {
    for @ALL-CELL-NAMES Z @.candidates -> ($name, $candidate) {
        #dd $name, $candidate;
        $candidate.elems == 1 or next;
        without self.cell-number($name) {
            self.cell-number($name, my $val = $candidate.pick);
            note "[$name, $val]: Naked Single";
            return True;
        }
    }
    False;
}

method by-nine-cells(:$rows = True, :$columns = True, :$boxes = True) {
    my @nines;
    @nines.append: @ALL-CELL-ROWS.map(&row-names)       if $rows;
    @nines.append: @ALL-CELL-COLUMNS.map(&column-names) if $columns;
    @nines.append: @ALL-BOX-NAMES.map(&box-names)       if $boxes;

    @nines.map: -> @cells { 
        @cells Z @.candidates[ %CELL-INDEX{ @cells } ] 
    };
}

method infer-hidden-single() returns Bool {
    for self.by-nine-cells -> @cells {
        my $counts = bag(@cells.map({ .[1].keys }));
        for $counts.kv -> $k, $v {
            next unless $v == 1;
            for @cells -> ($name, $candidates) {
                next unless $candidates ∋ $k;
                without self.cell-number($name) {
                    self.cell-number($name, $k);
                    self.cell-candidates($name, set($k));
                    note "[$name, $k]: Hidden Single";
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

                if $c1.elems == 2 && $c2.elems == 2
                        && ($c1 ∩ ($val1, $val2)).elems == 2
                        && ($c2 ∩ ($val1, $val2)).elems == 2 {

                    my $changed = False;
                    for @cells.map({ .[0] }) -> $a-name {
                        next if $a-name ~~ any($name1, $name2);
                        next unless self.cell-candidates($a-name) ∩ ($val1, $val2);

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

method infer-naked-triple() returns Bool {
    for self.by-nine-cells -> @cells {
        for @cells.combinations(3) -> (($name1, $c1), ($name2, $c2), ($name3, $c3)) {
            for @ALL-CELL-NUMBERS.combinations(3) -> ($val1, $val2, $val3) {

                if $c1.elems <= 3 && $c2.elems <= 3 && $c2.elems <= 3
                        && ($c1 ∪ ($val1, $val2, $val3)).elems == 3
                        && ($c2 ∪ ($val1, $val2, $val3)).elems == 3
                        && ($c3 ∪ ($val1, $val2, $val3)).elems == 3 {

                    my $changed = False;
                    for @cells.map({ .[0] }) -> $a-name {
                        next if $a-name ~~ any($name1, $name2, $name3);
                        next unless self.cell-candidates($a-name) ∩ ($val1, $val2, $val3);

                        self.remove-candidate($a-name, $val1);
                        self.remove-candidate($a-name, $val2);
                        self.remove-candidate($a-name, $val3);
                        $changed = True;
                    }

                    if $changed {
                        note "[$name1/$name2/$name3, $val1/$val2/$val3]: Naked Triple";
                        return True;
                    }
                }
            }
        }
    }

    False;
}

method infer-naked-quad() returns Bool {
    for self.by-nine-cells -> @cells {
        for @cells.combinations(4) -> (($name1, $c1), ($name2, $c2), ($name3, $c3), ($name4, $c4)) {
            for @ALL-CELL-NUMBERS.combinations(4) -> ($val1, $val2, $val3, $val4) {

                if $c1.elems <= 3 && $c2.elems <= 3 && $c3.elems <= 3 && $c4.elems <= 3
                        && ($c1 ∪ ($val1, $val2, $val3, $val4)).elems == 4
                        && ($c2 ∪ ($val1, $val2, $val3, $val4)).elems == 4
                        && ($c3 ∪ ($val1, $val2, $val3, $val4)).elems == 4 
                        && ($c4 ∪ ($val1, $val2, $val3, $val4)).elems == 4 {

                    my $changed = False;
                    for @cells.map({ .[0] }) -> $a-name {
                        next if $a-name ~~ any($name1, $name2, $name3, $name4);
                        next unless self.cell-candidates($a-name) ∩ ($val1, $val2, $val3, $val4);

                        self.remove-candidate($a-name, $val1);
                        self.remove-candidate($a-name, $val2);
                        self.remove-candidate($a-name, $val3);
                        self.remove-candidate($a-name, $val4);
                        $changed = True;
                    }

                    if $changed {
                        note "[$name1/$name2/$name3/$name4, $val1/$val2/$val3/$val4]: Naked Quad";
                        return True;
                    }
                }
            }
        }
    }

    False;
}

method infer-hidden-pair() returns Bool {
    for self.by-nine-cells -> @cells {
        for @cells.combinations(2) -> (($name1, $c1), ($name2, $c2)) {
            for @ALL-CELL-NUMBERS.combinations(2) -> ($val1, $val2) {
                if ($c1.elems > 2 || $c2.elems > 2)
                        && ($c1 ∩ ($val1, $val2)).elems == 2
                        && ($c2 ∩ ($val1, $val2)).elems == 2 
                        && not so @cells.first: -> ($a-name, $a-c) {
                                  $a-name ne $name1
                               && $a-name ne $name2
                               && $a-c ∩ ($val1, $val2)
                           } {

                    self.cell-candidates($name1, set($val1, $val2));
                    self.cell-candidates($name2, set($val1, $val2));
                    note "[$name1/$name2, $val1/$val2]: Hidden Pair";
                    return True;
                }
            }
        }
    }

    False
}

method infer-hidden-triple() returns Bool {
    for self.by-nine-cells -> @cells {
        for @cells.combinations(3) -> (($name1, $c1), ($name2, $c2), ($name3, $c3)) {
            for @ALL-CELL-NUMBERS.combinations(3) -> ($val1, $val2, $val3) {
                if ($c1.elems > 2 || $c2.elems > 2 || $c3.elems > 2)
                        && ($c1 ∩ ($val1, $val2, $val3)).elems >= 2
                        && ($c2 ∩ ($val1, $val2, $val3)).elems >= 2
                        && ($c3 ∩ ($val1, $val2, $val3)).elems >= 2
                        && ($c1 ∪ $c2 ∪ $c3) ∖ ($val1, $val2, $val3)
                        && not so @cells.first: -> ($a-name, $a-c) {
                                  $a-name ne $name1
                               && $a-name ne $name2
                               && $a-name ne $name3
                               && $a-c ∩ ($val1, $val2, $val3)
                           } {

                    self.only-candidates($name1, ($val1, $val2, $val3));
                    self.only-candidates($name2, ($val1, $val2, $val3));
                    self.only-candidates($name3, ($val1, $val2, $val3));
                    note "[$name1/$name2/$name3, $val1/$val2/$val3]: Hidden Triple";
                    return True;
                }
            }
        }
    }

    False
}

method infer-hidden-quad() returns Bool {
    for self.by-nine-cells -> @cells {
        for @cells.combinations(4) -> (($name1, $c1), ($name2, $c2), ($name3, $c3), ($name4, $c4)) {
            for @ALL-CELL-NUMBERS.combinations(4) -> ($val1, $val2, $val3, $val4) {
                if ($c1.elems > 2 || $c2.elems > 2 || $c3.elems > 2 || $c4.elems > 2)
                        && ($c1 ∩ ($val1, $val2, $val3, $val4)) >= 2
                        && ($c2 ∩ ($val1, $val2, $val3, $val4)) >= 2
                        && ($c3 ∩ ($val1, $val2, $val3, $val4)) >= 2
                        && ($c4 ∩ ($val1, $val2, $val3, $val4)) >= 2
                        && ($c1 ∪ $c2 ∪ $c3 ∪ $c4) ∖ ($val1, $val2, $val3, $val4)
                        && not so @cells.first: -> ($a-name, $a-c) {
                                  $a-name ne $name1
                               && $a-name ne $name2
                               && $a-name ne $name3
                               && $a-name ne $name4
                               && $a-c ∩ ($val1, $val2, $val3, $val4)
                           } {

                    self.only-candidates($name1, ($val1, $val2, $val3, $val4));
                    self.only-candidates($name2, ($val1, $val2, $val3, $val4));
                    self.only-candidates($name3, ($val1, $val2, $val3, $val4));
                    self.only-candidates($name4, ($val1, $val2, $val3, $val4));
                    note "[$name1/$name2/$name3/$name4, $val1/$val2/$val3/$val4]: Hidden Quad";
                    return True;
                }
            }
        }
    }

    False
}

method infer-pointing-pair() returns Bool {
    for self.by-nine-cells(:!boxes) -> @cells {
        for 0..2, 3..5, 6..8 -> @range {
            for @cells[@range].combinations(2) -> (($name1, $c1), ($name2, $c2)) {
                for @ALL-CELL-NUMBERS -> $val {
                    if $c1 ∋ $val && $c2 ∋ $val 
                            && not so box-names-for($name1).first: -> $a-name {
                                      $a-name ne $name1
                                   && $a-name ne $name2
                                   && self.cell-candidates($a-name) ∋ $val
                               } {

                        my $changed = False;
                        for @cells -> ($a-name, $a-c) {
                            next unless $a-c ∋ $val;
                            next if $a-name eq $name1;
                            next if $a-name eq $name2;
                            self.remove-candidate($a-name, $val);
                            $changed = True;
                        }

                        if $changed {
                            note "[$name1/$name2, $val]: Pointing Pair";
                            return True;
                        }
                    }
                }
            }
        }
    }

    False
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
        my $rc  = $row ~ $col;
        my $it  = self.cell-number($rc);
        my $set = self.cell-candidates($rc);
        my $val = $prow * 3 + $pcol + 1;
        $fh.print("│") if $pcol == 0 && $col != 1;
        $fh.print(
               ($it // 0) == $val ?? chr(0x245f + $val)
            !!        $set ∋ $val ?? $val
            !!                       ' '
        );
        if $col == 9 && $pcol == 2 {
            $fh.print("\n");
            $fh.say("───┼" x 8 ~ "───") if $prow == 2 && $row ne 'I';
        }
    }
    Nil
}

method solve() {
    self.initialize-candidates;
    self.show-possible;
    say "#" x 150;
    loop {
        last unless False
            or self.infer-naked-single
            or self.infer-hidden-single
            or self.infer-naked-pair
            or self.infer-hidden-pair
            or self.infer-pointing-pair
            or self.infer-naked-triple
            or self.infer-hidden-triple
            or self.infer-naked-quad
            ;
        self.revise-candidates;

        self.show-possible;
        prompt "#" x 150;
    }
}
