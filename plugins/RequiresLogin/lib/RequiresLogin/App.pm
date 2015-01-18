package RequiresLogin::App;

use strict;
no warnings qw( redefine );

sub initializer {}

require MT::App;
*MT::App::_is_commenter = sub {
    my $app = shift;
    my ( $author ) = @_;
    return 0 if $author->is_superuser;
    my @author_perms
        = $app->model('permission')
        ->load( { author_id => $author->id, blog_id => '0' },
        { not => { blog_id => 1 } } );
    my $commenter = -1;
    my $commenter_blog_id;
    for my $perm (@author_perms) {
        my $permissions = $perm->permissions;
        next unless $permissions;
        $permissions =~ s/,//g;
        $permissions =~ s/'comment'//;
        if ( $permissions eq "'view'" ) {
            $commenter_blog_id = $perm->blog_id unless $commenter_blog_id;
            $commenter = 1;
            next;
        }
        return 0;
    }
    if ( -1 == $commenter ) {
        my $sys_perms             = MT::Permission->perms('system');
        my $has_system_permission = 0;
        foreach ( @$sys_perms ) {
            if ( $author->permissions(0)->has( $_->[0] ) ) {
                $has_system_permission = 1;
                last;
            }
        }
        return $app->error(
            $app->translate(
                'Sorry, but you do not have permission to access any blogs or websites within this installation. If you feel you have reached this message in error, please contact your Movable Type system administrator.'
            )
        ) unless $has_system_permission;
        return -1;
    }
    return $commenter_blog_id;
};

sub _post_run {
    my $app = MT->instance();
    $app->run_callbacks( 'MT::App::CMS::Members::post_run', @_ );
    # Alias for Members Plugin of PowerCMS
}

1;