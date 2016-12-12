use Test;
class Test::Fuzz {
	class Fuzzer {...}
	my Fuzzer %fuzzers;
	class Fuzzer {
		has				$.name;
		has 			@.data;
		has Callable	$.get-data;
		has Block		$.func;
		has 			$.returns;
		has Callable	$.test;

		#method run() is hidden-from-backtrace {
		method run() {
			subtest {
				@!data = $.get-data.() unless @!data;
				for @.data -> @data {
					my $return = $.func.(|@data);
					$return.exception.throw if $return ~~ Failure;
					CATCH {
						default {
							lives-ok {
								.throw
							}, "{ $.name }({ @data.map({.defined ?? $_ !! "({ $_.^name })"}).join(", ") })"
						}
					}
					if $!test.defined and not $!test($return) {
						flunk "{ $.name }({ @data.map(*.perl).join(", ") })"
					}
					pass "{ $.name }({ @data.map(*.perl).join(", ") })"
				}
			}, $.name
		}
	}

	my Iterable %generator;

	multi fuzz-generator(::Type) is export is rw {
		%generator{Type.^name};
	}

	multi fuzz-generator(Str \type) is export is rw {
		%generator{type};
	}

	fuzz-generator("Str") = gather {
		take "";
		take "a";
		take "a" x 99999;
		take "áéíóú";
		take "\n";
		take "\r";
		take "\t";
		take "\r\n";
		take "\r\t\n";
		loop {
			take (0.chr .. 0xc3bf.chr).roll((^999).pick).join
		}
	};

	fuzz-generator("UInt") = gather {
		take 0;
		take 1;
		take 3;
		take 9999999999;
		take $_ for (^10000000000).roll(*)
	};

	fuzz-generator("Int")	= gather {
		for @( %generator<UInt> ).grep({.defined}) -> $int {
			take -$int;
		}
	};


	sub fuzz(Routine $func, Int() :$counter = 100, Callable :$test, :@generators is copy) is export {
		if @generators {
			@generators .= map: { ($^type || $^type.^name), all() };
		} else {
			@generators = $func.signature.params.map({:type(.type.^name ~ .modifier), :constraints(.constraints)})
		}
		my $get-data = sub {
			do if $func.signature.params.elems > 0 {
				do if $func.signature.params.elems == 1 {
					with @generators[0] -> (:$type, :$constraints) {
						$?CLASS.generate($type, $constraints, $counter).map: -> $item {[$item]}
					}
				} else {
					([X] @generators.map(-> (:$type, :$constraints) {
						$?CLASS.generate($type, $constraints, $counter)
					}))
				}.pick: $counter
			} else {
				Empty
			}
		};

		my $name	= $func.name;
		my $returns	= $func.signature.returns;

		%fuzzers.push($name => Fuzzer.new(:$name, :$func, :$get-data, :$returns, :$test))
	}

	multi trait_mod:<is> (Routine $func, :%fuzzed!) is export {
		fuzz($func, |%fuzzed);
	}

	multi trait_mod:<is> (Routine $func, :$fuzzed!) is export {
		fuzz($func);
	}

	method generate(Test::Fuzz:U: Str \type, Mu:D $constraints, Int $size) {
		my Mu @ret;
		my Mu @undefined;
		my $type = type ~~ /^^
			$<type>	= (\w+)
			[
				':'
				$<def>	= (<[UD]>)
			]?
		$$/;
		my \test-type		= ::(~$type<type>);
		my $loaded-types	= set |::.values.grep(not *.defined);
		my $builtin-types	= set |%?RESOURCES<classes>.IO.lines.map({::($_)});
		my $types			= $loaded-types ∪ $builtin-types;
		#my $types			= $builtin-types;
		my @types			= $types.keys.grep(sub (Mu \item) {
			my Mu:U \i = item;
			return so i ~~ test-type;
			CATCH {return False}
		});
		@undefined = @types.grep(sub (Mu \item) {
			my Mu:U \i = item;
			return so i ~~ $constraints;
			CATCH {return False}
		}) if not $type<def>.defined or ~$type<def> eq "U";
		my %indexes := BagHash.new;
		my %gens := @types.map(*.^name) ∩ %generator.keys;
		while @ret.elems < $size {
			for %gens.keys -> $sub {
				my $item = %generator{$sub}[%indexes{$sub}++];
				@ret.push: $item if $item ~~ test-type & $constraints;
			}
		}
		@ret.unshift: |@undefined if @undefined;
		@ret
	}

	method run-tests(Test::Fuzz:U: @funcs = %fuzzers.keys.sort) {
		for %fuzzers{@funcs}.map(|*) -> $fuzz {
			$fuzz.run
		}
	}
}
