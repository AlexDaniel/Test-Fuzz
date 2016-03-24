use Test;
class Test::Fuzz {
	class Fuzzer {
		has		$.name;
		has 		@.data;
		has Block	$.func;
		has 		$.returns;
		has Callable	$.test;

		method run() is hidden-from-backtrace {
			subtest {
				for @.data -> @data {
					my $return = $.func.(|@data);
					$return.exception.throw if $return ~~ Failure;
					CATCH {
						default {
							lives-ok {
								.throw
							}, "{ $.name }({ @data.join(", ") })"
						}
					}
					if $!test.defined and not $!test($return) {
						flunk "{ $.name }({ @data.join(", ") })"
					}
					pass "{ $.name }({ @data.join(", ") })"
				}
			}, $.name
		}
	}

	my Iterable %generator{Mu:U};

	sub fuzz-generator(::Type) is export is rw {
		%generator{Type};
	}

	fuzz-generator(UInt) = gather {
		take 0;
		take 1;
		take 3;
		take 9999999999;
		take $_ for (^10000000000).roll(*)
	};

	fuzz-generator(Int)	= gather for @( %generator{UInt} ) -> $int {
		take $int;
		take -$int unless $int == 0;
	};

	my Fuzzer @fuzzers;

	sub fuzz(Routine $func, Int() :$counter = 100, Callable :$test) is export {
		my \params = $func.signature.params;
		my @data = ([X] params.map(-> \param {
			my $type = param.type;
			$?CLASS.generate($type, $counter)
		}))[^$counter];
		if params.elems <= 1 {
			@data = @data[0].map(-> $item {[$item]});
		}

		my $name	= $func.name;
		my $returns	= $func.signature.returns;

		@fuzzers.push(Fuzzer.new(:$name:$func:@data:$returns:$test))
	}

	multi trait_mod:<is> (Routine $func, :%fuzzed!) is export {
		dd %fuzzed;
		fuzz($func, |%fuzzed);
	}

	multi trait_mod:<is> (Routine $func, :$fuzzed!) is export {
		fuzz($func);
	}

	method generate(Test::Fuzz:U: ::Type, Int() \size) {
		my $ret;
		if %generator{Type}:exists {
			$ret = %generator{Type}[^size]
		}
		$ret
	}

	method run-tests(Test::Fuzz:U:) {
		#say @fuzzers;
		for @fuzzers -> $fuzz {
			$fuzz.run;
		}
	}
}
