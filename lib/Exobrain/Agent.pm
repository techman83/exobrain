package Exobrain::Agent;
use Moose::Role;
use Exobrain;
use Exobrain::Types qw(Exobrain);

# ABSTRACT: Agent role for Exobrain agents
# VERSION

=head1 SYNOPSIS

    use Moose;
    with 'Exobrain::Agent';

=head1 DESCRIPTION

This role provides a number of utility methods and attributes to
Exobrain agents. Most agents will prefer to use the
L<Exobrain::Agent::Poll> or L<Exobrain::Agent::Run> roles
instead, and which in turn consume this role and hence provide
its functionality.

Where possible, all attributes provided by this role are lazily
generated, including lazily loading modules.

=method exobrain

    $self->exobrain->watch_loop(...);

Returns an L<Exobrain> object.

=cut

has exobrain => (
    is => 'ro',
    isa => Exobrain,
    lazy => 1,
    builder => '_build_exobrain',
);

sub _build_exobrain { return Exobrain->new; }

=method component

    my $component = $self->component;

Exobrain components all share the same configuration and cache,
and are often packaged as separate distributions. This method
returns the current component name.

By default this is the same as the class name with
'Exobrain::Agent::' stripped off. Agents and roles which are
part of a specific component should override this attribute
(or supply their own default).

=cut

has component => (
    is => 'ro',
    isa => 'Str',
    lazy => 1,
    builder => '_build_component',
);

method _build_component() {
    if (my $method = $self->can("component_name") ) {
        return $self->$method;
    }

    my $component = ref($self);
    $component =~ s/Exobrain::Agent:://;
    return $component;
}

=method config

    my $user = $self->config->{user};

Returns the config for our current component.
Use C<$self->exobrain->config> instead if you want the I<top-level>
config.

=cut

has config => (
    is => 'ro',
    lazy => 1,
    builder => '_build_config',
);

# By using the component name as the heading for our config, it's easy
# to clearly tell which config belongs where.

method _build_config() {
    return $self->exobrain->config->{ $self->component };
}

=method cache

    my $cache = $self->cache;

Returns an L<Exobrain::Cache> object, with a namespace of
C<$self->component>.

=cut

has cache => (
    is => 'ro',
    lazy => 1,
    builder => '_build_cache',
);

method _build_cache() {
    eval "use Exobrain::Cache; 1;" or die $@;   # Lazy load module
    return Exobrain::Cache->new( namespace => $self->component );
}

=method json

    my $json = $self->json;

Returns a L<JSON::Any> object.

=cut

has json => (
    is => 'ro',
    lazy => 1,
    builder => '_build_json',
);

method _build_json() {
    eval "use JSON::Any; 1;" or die $@;
    return JSON::Any->new;
}

=method cached

    BEGIN { with 'Exobrain::Agent'; }

    cached last_status => (
        isa => 'Int',
        default => 0,
    );

This keyword marks an attribute as I<cached>. It will persist between
runs of the agent, and updating the attribute will update its value
in the cache.

A default I<must> be provided so the cache can be populated the first
time. The attribute will default to 'rw'. You can override this, but
I don't know why you would.

You may have to load C<Exobrain::Agent> (or derived role) inside a
C<BEGIN> block for this keyword to be properly available.

The cache key will always be the fully qualified (class + attribute)
name of the *derived* class, but you probably don't care about such
internal minutiaes.

NOTE: This code currently does not check the difference between attributes
which do not exist, and those that have been cached as undef. If 'undef'
is a valid value, then do your caching manually (or submit a patch
for this keyword!).

=cut

func cached($name, %args) {

    if (not exists $args{default}) {
        require Carp;
        Carp::croak "cached '$name' called with no 'default' attribute";
    }

    my $default = delete $args{default};

    # Find the 'has' function in the caller's namespace.
    # TODO: Merge this with identical code from Exobrain::Message

    my ($uplevel) = caller();
    my $uphas     = join('::', $uplevel, 'has');
    my $cache_key = join('::', $uplevel, $name);

    # Coderef to read the value out of the cache.

    my $read_cache_sub = sub {
        my ($self) = @_;

        return $self->cache->get( $cache_key ) // $default;
    };

    # Coderef to put values back in the cache.

    my $write_cache_sub = sub {
        my ($self, $new, $old) = @_;

        $self->cache->set( $cache_key, $new );

        return;
    };

    no strict 'refs';   # Using a string as a subref is cool, Perl.

    return $uphas->(
        $name => (
            is      => 'rw',
            default => $read_cache_sub,
            trigger => $write_cache_sub,
            %args,
        )
    );
}

1;
