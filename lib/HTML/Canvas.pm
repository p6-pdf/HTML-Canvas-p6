use v6;
use PDF::Content::Util::TransformMatrix;

class HTML::Canvas {
    has Numeric @.TransformationMatrix is rw = [ 1, 0, 0, 1, 0, 0, ];
    has Pair @.calls;
    has Routine $.callback;
    has $!font-style = '10pt times-roman';

    method !transform(|c) {
        my @matrix = PDF::Content::Util::TransformMatrix::transform-matrix(|c);
        @!TransformationMatrix = PDF::Content::Util::TransformMatrix::multiply(@!TransformationMatrix, @matrix);
    }

    our %API is export(:API) = BEGIN %(
        :scale(method (Numeric $x, Numeric $y) {
                      self!transform: :scale[$x, $y];
                  }),
        :rotate(method (Numeric $angle) {
                      self!transform: :rotate($angle);
                  }),
        :translate(method (Numeric $angle) {
                      self!transform: :translate($angle);
                  }),
        :transform(method (Numeric \a, Numeric \b, Numeric \c, Numeric \d, Numeric \e, Numeric \f) {
                      @!TransformationMatrix = PDF::Content::Util::TransformMatrix::multiply(@!TransformationMatrix, [a, b, c, d, e, f]);
                      }),
        :setTransform(method (Numeric \a, Numeric \b, Numeric \c, Numeric \d, Numeric \e, Numeric \f) {
                          my @identity = PDF::Content::Util::TransformMatrix::identity;
                          @!TransformationMatrix = PDF::Content::Util::TransformMatrix::multiply(@identity, [a, b, c, d, e, f]);
                      }),
        :arc(method (Numeric $x, Numeric $y, Numeric $radius, Numeric $startAngle, Numeric $endAngle, Bool $counterClockwise?) { }),
        :beginPath(method () {}),
        :rect(method (Numeric $x, Numeric $y, Numeric $w, Numeric $h) { }),
        :strokeRect(method (Numeric $x, Numeric $y, Numeric $w, Numeric $h) { }),
        :fillText(method (Str $text, Numeric $x, Numeric $y, Numeric $max-width?) { }),
        :stroke(method () {}),
    );

    method !add-call(Str $name, *@args) {
        self.calls.push: ($name => @args);
        .($name, |@args, :obj(self)) with self.callback;
    }

    method font is rw {
        Proxy.new(
            FETCH => sub ($) { $!font-style },
            STORE => sub ($, Str $!font-style) {
                self!add-call('font', $!font-style);
            }
        );
    }

    method js(Str :$context = 'ctx', :$sep = "\n") {
        use JSON::Fast;
        @!calls.map({
            my $name = .key;
            my @args = .value.map: { to-json($_) };
            my \fmt = $name eq 'font'
                ?? '%s.%s = %s;'
                !! '%s.%s(%s);';
            sprintf fmt, $context, $name, @args.join(", ");
        }).join: $sep;
    }

    method render($renderer, :@calls = self.calls) {
        my $callback = $renderer.callback;
        my $obj = self.new: :$callback;
        $obj."{.key}"(|.value)
            for @calls;
    }

    method can(Str \name) {
        my @meth = callsame;
        if !@meth {
            with %API{name} -> &meth {
                @meth.push: method (*@a) {
                    &meth(self, |@a);
                    self!add-call(name, |@a);
                };
                self.^add_method(name, @meth[0]);
            }
        }
        @meth;
    }
    method dispatch:<.?>(\name, |c) is raw {
        self.can(name) ?? self."{name}"(|c) !! Nil
    }
    method FALLBACK(Str \name, |c) {
        self.can(name)
            ?? self."{name}"(|c)
            !! die die X::Method::NotFound.new( :method(name), :typename(self.^name) );
    }
}
