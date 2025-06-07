% a Value unified with the Expected value and report to the current output if it does not unified
test_unify(Value, Expected) :-
    (nonvar(Value), Value = Expected) ->
        true
    ; (
        current_output(Out),
        phrase_to_stream(("expect value to unified with: \n\n", portray_clause_(Expected), "\nbut got: \n\n", portray_clause_(Value)), Out),
        false
    ).

% a Value unified with the Expected value and report to the current output if it does not unified
test_eq(Value, Expected):-
    Value == Expected ->
        true
    ; (
        current_output(Out),
        phrase_to_stream(("expected: \n\n", portray_clause_(Expected), "\nbut got: \n\n", portray_clause_(Value)), Out),
        false
    ).