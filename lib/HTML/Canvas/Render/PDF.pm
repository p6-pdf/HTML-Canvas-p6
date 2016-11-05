use v6;
class HTML::Canvas::Render::PDF {

    use HTML::Canvas :API;
    use PDF::Content;
    has PDF::Content $.gfx handles <content> is required;
    has $.height is required; # canvas height in points
    has $.font-object is required;
    has @!ctm = [1, 0, 0, 1, 0, 0]; #| canvas transform matrix

    method callback {
        sub ($op, |c) {
            if self.can: "{$op}" {
                self."{$op}"(|c);
            }
            else {
                %API{$op}:exists
                    ?? warn "unimplemented Canvas 2d API call: $op"
                    !! die "unknown Canvas 2d API call: $op";    
            }
        }
    }

    sub pt(Numeric \l) { l }

    method !coords(Numeric \x, Numeric \y) {
        #| translate back to canvas coordinates
        my (\x1, \y1) = PDF::Content::Util::TransformMatrix::dot(@!ctm, x, y);
        PDF::Content::Util::TransformMatrix::inverse-dot(@!ctm, x1, $!height - y1);
    }

    # ref: http://stackoverflow.com/questions/1960786/how-do-you-draw-filled-and-unfilled-circles-with-pdf-primitives
    sub draw-circle(\g, Numeric \r) {
        my Numeric \magic = r * 0.551784;
        g.MoveTo(-r, 0);
        g.CurveTo(-r, magic, -magic, r,  0, r);
        g.CurveTo(magic, r,  r, magic,  r, 0);
        g.CurveTo(r, -magic,  magic, -r,  0, -r);
        g.CurveTo(-magic, -r,  -r, -magic,  -r, 0);
    }

    method !transform( |c ) {
	my Numeric @tm = PDF::Content::Util::TransformMatrix::transform-matrix( |c );
        @!ctm = PDF::Content::Util::TransformMatrix::multiply(@!ctm, @tm);
	$!gfx.ConcatMatrix( @tm );
    }

    my %Dispatch = BEGIN %(
        scale     => method (Numeric \x, Numeric \y) { self!transform(|scale => [x, y]) },
        rotate    => method (Numeric \angle) { self!transform(|rotate => [ angle, ]) },
        translate => method (Numeric \x, Numeric \y) { self!transform(|translate => [x, -y]) },
        transform => method (Numeric \a, Numeric \b, Numeric \c, Numeric \d, Numeric \e, Numeric \f) {
            self!transform(|matrix => [a, b, c, d, e, -f]);
        },
        setTransform => method (Numeric \a, Numeric \b, Numeric \c, Numeric \d, Numeric \e, Numeric \f) {
            my @ctm-inv = PDF::Content::Util::TransformMatrix::inverse(@!ctm);
            my @diff = PDF::Content::Util::TransformMatrix::multiply([a, b, c, d, e, -f], @ctm-inv);
                self!transform( |matrix => @diff )
                    unless PDF::Content::Util::TransformMatrix::is-identity(@diff);
        },
        arc => method (Numeric \x, Numeric \y, Numeric \r, Numeric \startAngle, Numeric \endAngle, Bool $anti-clockwise?) {
            # stub. ignores start and end angle; draws a circle
            warn "todo: arc start/end angles"
                unless endAngle - startAngle =~= 2 * pi;
            $!gfx.ConcatMatrix:  PDF::Content::Util::TransformMatrix::translate(|self!coords(x, y) );
            draw-circle($!gfx, r);
        },
        beginPath => method () {
            $!gfx.Save;
        },
        stroke => method () {
            $!gfx.Stroke;
            $!gfx.Restore;
        },
        fillText => method (Str $text, Numeric $x, Numeric $y, Numeric $maxWidth?) {
            self.font;
            my $scale;
            if $maxWidth && $maxWidth > 0 {
                my Numeric \width = .face.stringwidth($text, .em) with $!font-object;
                $scale = 100 * $maxWidth / width
                    if width > $maxWidth;
            }

            $!gfx.Save;
            $!gfx.BeginText;
            $!gfx.HorizScaling = $_ with $scale;
            $!gfx.text-position = self!coords($x, $y);
            $!gfx.print($text);
            $!gfx.EndText;
            $!gfx.Restore
        },
        font => method (Str $font-style?) {
            my \pdf-font = $!gfx.use-font($!font-object.face);

            with $font-style {
                $!font-object.css-font-prop = $_;
                $!gfx.font = [ pdf-font, $!font-object.em ];
            }
            else {
                $!gfx.font //= [ pdf-font, $!font-object.em ];
            }
        },
        rect => method (\x, \y, \w, \h) {
            unless $!gfx.fillAlpha =~= 0 {
                $!gfx.Rectangle( |self!coords(x, y + h), pt(w), pt(h) );
                $!gfx.ClosePath;
            }
        },
        strokeRect => method (\x, \y, \w, \h) {
            $!gfx.Rectangle( |self!coords(x, y + h), pt(w), pt(h) );
            $!gfx.CloseStroke;
        },
    );

    method can(\name) {
        my @can = callsame;
        unless @can {
            with %Dispatch{name} {
                @can.push: $_;
                self.^add_method( name, @can[0] );
            }
        }
        @can;
    }

    method dispatch:<.?>(\name, |c) is raw {
        self.can(name) ?? self."{name}"(|c) !! Nil
    }
    method FALLBACK(\name, |c) {
        self.can(name)
            ?? self."{name}"(|c)
            !! die X::Method::NotFound.new( :method(name), :typename(self.^name) );
    }

}
