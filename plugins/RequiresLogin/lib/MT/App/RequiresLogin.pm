package MT::App::RequiresLogin;

use strict;
use base qw( MT::App MT::App::CMS );
use MT;
use MT::App::CMS;
@MT::App::RequiresLogin = qw( MT::App );

sub init_request {
    my $app = shift;
    $app->SUPER::init_request( @_ );
    if ( my $mode = $app->mode ) {
        if ( $mode eq 'default' ) {
            $app->{ requires_login } = 1;
        }
    }
    # $app->run_callbacks( 'MT::App::CMS::Members::init_request', @_ );
    # Alias for Members Plugin of PowerCMS
    $app;
}

sub debug {
    my $app = shift;
    my $param = {};
    $param->{ message } = $app->translate( 'Welcome to Movable Type' );
    return $app->login_form( $param, 'default' );
}

sub default {
    my $app = shift;
    my $return_url = $app->param( 'return_url' );
    if (! $return_url ) {
        if ( my $blog = $app->blog ) {
            $return_url = $blog->site_url;
        }
    }
    if (! $return_url ) {
        $return_url = $app->base;
    }
    $app->redirect( $return_url );
}

sub signup {
    my $app = shift;
    my $component = MT->component( 'RequiresLogin' );
    my %opt = @_;
    my $param = {};
    my $registration = MT->config( 'RequiresLoginRegistration' )
        or $app->handle_error( $app->translate( 'Signing up is not allowed.' ) );
    # $app->{ template_dir } = 'comment';
    $param->{ $_ } = $app->param( $_ )
        foreach qw( blog_id entry_id static nickname email username return_url );
    if ( $registration ) {
        if ( my $blog = $app->blog ) {
            if ( my $provider = MT->effective_captcha_provider( $blog->captcha_provider ) ) {
                $param->{ captcha_fields } = $provider->form_fields( $blog->id );
            }
        }
        $param->{ $_ } = $opt{ $_ } foreach keys %opt;
        $param->{ 'auth_mode_' . MT->config( 'AuthenticationModule' ) } = 1;
        if ( $app->errstr ) {
            $param->{ error } = $app->errstr;
        }
        $app->{ plugin_template_path } = File::Spec->catdir( $component->path, 'tmpl' );
        return $app->build_page( 'signup.tmpl', $param );
    }
    $app->handle_error( $app->translate( 'Signing up is not allowed.' ) );
}

sub logout {
    MT::App::logout( @_ );
}

sub withdraw {
    my $app = shift;
    if ( $app->request_method ne 'POST' ) {
        $app->error( $app->translate( 'Invalid request' ) );
    }
    $app->validate_magic
        or return $app->trans_error( 'Invalid request' );
    my $component = MT->component( 'RequiresLogin' );
    if (! MT->config( 'RequiresLoginRegistration' ) ) {
        return $app->handle_error( $app->translate( 'Signing up is not allowed.' ) );
    }
    if (! $app->user ) {
        my $param = {};
        $param->{ message } = $app->translate( 'Your Movable Type session has ended. If you wish to sign in again, you can do so below.' );
        return $app->login_form( $param );
    }
    my $user = $app->user;
    $app->logout();
    $user->status( 2 );
    $user->save or die $user->errstr;
    my $return_url = $app->param( 'return_url' );
    $app->run_callbacks( 'members_post_secedes.user', $app, \$user, \$return_url );
    # Alias for Members Plugin of PowerCMS
    # TODO::Mail or Callback
    if ( $return_url ) {
        return $app->redirect( $return_url );
    }
    my $param = {};
    $param->{ message } = $component->translate( 'You have unsubscribed from Movable Type.' );
    return $app->login_form( $param, 'default' );
}

sub do_signup {
    my $app = shift;
    if (! MT->config( 'RequiresLoginRegistration' ) ) {
        return $app->handle_error( $app->translate( 'Signing up is not allowed.' ) );
    }
    my $component = MT->component( 'RequiresLogin' );
    # $app->{ template_dir } = 'comment';
    my $q   = $app->param;
    if ( $app->request_method ne 'POST' ) {
        $app->error( $app->translate( 'Invalid request' ) );
    }
    my $param = {};
    $param->{ $_ } = $q->param( $_ )
        foreach qw( blog_id entry_id static email url username nickname return_url );
    my $blog = $app->model( 'blog' )->load( $param->{ blog_id } || 0 );
    my $filter_result = $app->run_callbacks( 'api_save_filter.author', $app );
    if (! $blog ) {
        my $website = MT->model( 'website' )->load( undef,{ limit => 1 } );
        $app->param( 'blog_id', $website->id );
        $param->{ blog_id } = $website->id;
        $blog = $website;
    }
    $app->run_callbacks( 'members_pre_save.new_user', $app );
    # Alias for Members Plugin of PowerCMS
    my $user = $app->create_user_pending( $param ) if $filter_result;
    if (! $user ) {
        return signup( $app );
    }
    ## Assign default role
    $user->add_default_roles;
    my $role = $component->get_config_value( 'requireslogin_default_role_id', 'blog:' . $blog->id );
    if ( $role ) {
        require MT::Role;
        require MT::Association;
        my $r = MT::Role->load( $role );
        MT::Association->link( $user => $r => $blog );
    }
    $app->run_callbacks( 'members_post_registration', $app, $user );
    # Alias for Members Plugin of PowerCMS
    my $original = $user->clone();
    $app->run_callbacks( 'api_post_save.author', $app, $user, $original );
    my $return_to = $param->{ static } || $param->{ return_url };
    MT::Util::start_background_task(
        sub {
            $app->_send_signup_confirmation(
                    $user->id, $user->email,
                    $return_to ? $return_to : undef,
                    $blog      ? $blog->id   : undef );
        }
    );
    $app->run_callbacks( 'members_post_save.new_user', $app, $user );
    # Alias for Members Plugin of PowerCMS
    $app->{ plugin_template_path } = File::Spec->catdir( $component->path, 'tmpl' );
    $app->build_page(
        'signup_thanks.tmpl',
        {   email => $user->email,
            return_url =>
                MT::Util::is_valid_url( $param->{ return_url } || $param->{ static } )
        }
    );
}

sub do_register {
    my $app = shift;
    my $component = MT->component( 'RequiresLogin' );
    my $email = $app->param( 'email' );
    my $token = $app->param( 'token' );
    my $return_to = $app->param( 'return_to' );
    my $blog_id = $app->param( 'blog_id' );
    ## Token expiration check
    require MT::Session;
    my $commenter;
    my $error;
    my $sess = MT::Session->load( { id => $token, kind => 'CR', email => $email } );
    if (! $sess ) {
        $error = 1;
    } else {
        if ( $sess->start() < ( time - 60 * 60 * 24 ) ) {
            $error = 1;
            $sess->remove;
        }
        $commenter = MT::Author->load( $sess->name );
    }
    if ( $error ) {
        $commenter->remove if $commenter;
        my $msg = $app->translate( 'Your confirmation has expired. Please register again.');
        if ( $return_to ) {
            $msg .= '&nbsp;' . $app->translate( '<a href="[_1]">Return to the original page.</a>',
                                                $return_to );
        }
        return $app->forward( 'signup', message => $msg );
    }
    $sess->remove;
    my $registration = MT->config( 'RequiresLoginRegistration' )
        or $app->handle_error( $app->translate( 'Signing up is not allowed.' ) );
    $commenter->status( MT::Author::ACTIVE() );
    $commenter->save
        or $app->forward( 'signup', error => $commenter->errstr );
    $app->log(
        {   message => $app->translate(
                "Commenter '[_1]' (ID:[_2]) has been successfully registered.",
                $commenter->name,
                $commenter->id
            ),
            level    => MT::Log::INFO(),
            class    => 'author',
            category => 'new',
        }
    );
    MT::Util::start_background_task(
        sub {
            $app->_send_registration_notification( $commenter, $blog_id );
        }
    );
    my $component = MT->component( 'RequiresLogin' );
    my $param = {};
    $param->{ return_url } = $return_to;
    $param->{ message } = $component->translate( 'Thanks for the confirmation. Please sign in.' );
    $app->login_form( $param, 'default' );
}

sub _send_registration_notification {
    my $app = shift;
    my ( $user, $blog_id ) = @_;
    my $component = MT->component( 'RequiresLogin' );
    my $email;
    if ( my $blog = $app->blog ) {
        $email = $component->get_config_value( 'requireslogin_signup_notify_to', 'blog:' . $blog->id );
    }
    if (! $email ) {
        $email = $component->get_config_value( 'requireslogin_signup_notify_to' );
    }
    if (! $email ) {
       $email = MT->config( 'EmailAddressMain' );
    }
    # TODO:: Notify Mail To
    return unless $email;
    my $url = $app->base . $app->mt_uri( mode => 'view',
                            args => { _type => 'author',
                                      id => $user->id } );
    my $param = {
        profile_url => $url
    };
    my $columns = $user->column_names;
    for my $col ( @$columns ) {
        $param->{ $col } = $user->$col;
    }
    my $tmpl = $app->_tmpl( 'commenter_notify' );
    require MT::Template::Context;
    my $ctx = MT::Template::Context->new;
    $ctx->stash( 'author', $user );
    if ( $blog_id ) {
        my $blog = MT::Blog->load( $blog_id );
        $ctx->stash( 'blog', $blog );
        $ctx->stash( 'blog_id', $blog_id );
    }
    require MT::Template;
    my $t = MT::Template->new;
    $t->text( $tmpl );
    my $body = $app->_build( $ctx, $tmpl, $param );
    my $subject;
    if ( $body =~ m!(^.*?)\n(.*$)!s ) {
        $subject = $1;
        $body = $2;
    }
    if (! $subject ) {
        $subject = $component->translate( '[_1] registered to the Movable Type', $user->nickname );
    }
    $app->_mail( $subject, $body, $email );
}

sub _send_signup_confirmation {
    my $app = shift;
    my $component = MT->component( 'RequiresLogin' );
    my ( $id, $email, $return_to, $blog_id ) = @_;
    my $blog;
    if ( $blog_id ) {
        $blog = $app->model( 'blog' )->load( $blog_id );
    }
    my $token = $app->make_magic_token;
    my $cgi_path = $app->config( 'CGIPath' );
    $cgi_path .= '/' unless $cgi_path =~ m!/$!;
    my $url = $cgi_path . MT->config( 'RequiresLoginScript' ) .
        $app->uri_params(
            mode => 'do_register',
            args   => {
                token => $token,
                email => $email,
                id    => $id,
                defined( $blog_id )   ? ( 'blog_id'   => $blog_id )   : (),
                defined( $return_to ) ? ( 'return_to' => $return_to ) : (),
            },
        );
    if ( ( $url =~ m!^/! ) && $blog ) {
        my ( $blog_domain ) = $blog->site_url =~ m|(.+://[^/]+)|;
        $url = $blog_domain . $url;
    }
    my $tmpl = $app->_tmpl( 'email_verification_email' );
    require MT::Template::Context;
    my $ctx = MT::Template::Context->new;
    if ( $blog ) {
        $ctx->stash( 'blog', $blog );
        $ctx->stash( 'blog_id', $blog->id );
    }
    my $param = {
        confirm_url => $url
    };
    my $body = $app->_build( $ctx, $tmpl, $param );
    my $subject;
    if ( $body =~ m!(^.*?)\n(.*$)!s ) {
        $subject = $1;
        $body = $2;
    }
    if (! $subject ) {
        $subject = $component->translate( 'Movable Type Account Confirmation' );
    }
    require MT::Session;
    my $sess = MT::Session->new;
    $sess->id( $token );
    $sess->kind( 'CR' ); # CR == Commenter Registration
    $sess->email( $email );
    $sess->name( $id );
    $sess->set( blog_id => $blog_id );
    $sess->start( time() );
    $sess->save;
    $app->_mail( $subject, $body, $email );
}

sub start_recover {
    my $app = shift;
    my $registration = MT->config( 'RequiresLoginRegistration' )
        or $app->handle_error( $app->translate( 'Signing up is not allowed.' ) );
    my ( $param ) = @_;
    $param ||= {};
    $param->{ email } = $app->param( 'email' );
    $param->{ return_to } = $app->param( 'return_to' ) || MT->config( 'ReturnToURL' ) || '';
    if ( $param->{ recovered } ) {
        $param->{ return_to } = MT::Util::encode_js( $param->{ return_to } );
    }
    $param->{ can_signin } = 0;
    $app->add_breadcrumb( $app->translate( 'Password Recovery' ) );
    my $blog_id = $app->param( 'blog_id' );
    $param->{ blog_id } = $blog_id;
    # my $tmpl = $app->load_tmpl( 'cms/dialog/recover.tmpl' );
    my $component = MT->component( 'RequiresLogin' );
    $app->{ plugin_template_path } = File::Spec->catdir( $component->path, 'tmpl' );
    my $tmpl = $app->load_tmpl( 'recover.tmpl' );
    $param->{ system_template } = 1;
    $tmpl->param( $param );
    return $tmpl;
}

sub recover {
    my $app = shift;
    my $registration = MT->config( 'RequiresLoginRegistration' )
        or $app->handle_error( $app->translate( 'Signing up is not allowed.' ) );
    require MT::CMS::Tools;
    MT::CMS::Tools::recover_password( $app, @_ );
}

sub new_pw {
    my $app = shift;
    my $registration = MT->config( 'RequiresLoginRegistration' )
        or $app->handle_error( $app->translate( 'Signing up is not allowed.' ) );
    require MT::CMS::Tools;
    MT::CMS::Tools::new_password( $app, @_ );
}

sub redirect_to_edit_profile {
    my $app = shift;
    return $app->redirect( $app->uri( mode => 'edit_profile' ) );
}

sub edit_profile {
    my $app = shift;
    my $registration = MT->config( 'RequiresLoginRegistration' )
        or $app->handle_error( $app->translate( 'Signing up is not allowed.' ) );
    if (! $app->user ) {
        my $param = {};
        $param->{ message } = $app->translate( 'Your Movable Type session has ended. If you wish to sign in again, you can do so below.' );
        return $app->login_form( $param );
    }
    # $app->{ template_dir } = 'comment';
    require MT::App::Comments;
    MT::App::Comments::edit_commenter_profile( $app );
}

sub handle_error {
    my ( $app, $message ) = @_;
    return $app->error( $message );
}

sub get_commenter_session {
    my $app = shift;
    my ( $sess, $user ) = MT::App::get_commenter_session( $app );
    if ( $sess && $user ) {
        return ( $sess, $user );
    }
    if ( my $user = $app->user ) {
        if ( my $sessid = $app->current_magic() ) {
            $sess = MT->model( 'session' )->load( { id => $sessid } );
        }
        return ( $sess, $user );
    }
}

sub _build {
    my ( $app, $ctx, $out, $param ) = @_;
    if ( defined( $param ) ) {
        for my $key( keys %$param ) {
            $ctx->{ __stash }{ vars }{ $key } = $param->{ $key };
        }
    }
    my $args;
    $args->{ blog } = $ctx->stash( 'blog' );
    $args->{ author } = $ctx->stash( 'author' );
    $app->run_callbacks( 'MT::App::CMS::Members::powercms_pre_build_tmpl', $app, $out, $args, $param );
    # Alias for Members Plugin of PowerCMS
    require MT::Builder;
    $out = $app->translate_templatized( $out );
    my $build = MT::Builder->new;
    my $tokens = $build->compile( $ctx, $out )
        or die $app->translate(
            "Parse error: [_1]", $build->errstr );
    defined( $out = $build->build( $ctx, $tokens ) )
        or die $app->translate(
            "Build error: [_1]", $build->errstr );
    return $out;
}

sub _tmpl {
    my ( $app, $tmpl ) = @_;
    my $component = MT->component( 'RequiresLogin' );
    my $tmpl = File::Spec->catfile( $component->path, 'tmpl', $tmpl . '.tmpl' );
    $tmpl = $app->load_tmpl( $tmpl );
    if ( ( ref $tmpl ) eq 'MT::Template' ) {
        return $tmpl->text;
    }
    return $tmpl;
}

sub _mail {
    my ( $app, $subject, $body, $to ) = @_;
    require MT::Mail;
    my $from_addr = MT->config( 'EmailAddressMain' );
    my $reply_to;
    if ( MT->config( 'EmailReplyTo' ) ) {
        $reply_to = MT->config( 'EmailAddressMain' );
    }
    if ( $to =~ /,/ ) {
        my @tos;
        my @ts = split( /,/, $to  );
        for my $t ( @ts ) {
            $t = MT::Util::trim( $t );
            $t = push( @tos, $t );
        }
        $to = \@tos;
    }
    my %head = (
        To => $to,
        From => $from_addr,
        Subject => $subject,
    );
    if ( $reply_to ) {
        $head{ 'Reply-To' } = $reply_to;
    }
    my $charset = MT->config( 'MailEncoding' ) || MT->config( 'PublishCharset' );
    $head{ 'Content-Type' } = qq(text/plain; charset="$charset");
    MT::Mail->send( \%head, $body )
        or die MT::Mail->errstr();
    return 1;
}

sub login_form {
    my $app = shift;
    my $params = shift;
    my $mode = shift;
    my $component = MT->component( 'RequiresLogin' );
    my $message = $params->{ message };
    delete( $params->{ message } );
    my @query_params;
    if (! $mode ) {
        for my $key ( keys %$params ) {
            push ( @query_params, { key => $key, value => $params->{ $key } } );
        }
        my $q = $app->param;
        my @ps = $q->param;
        for my $key ( @ps ) {
            push ( @query_params, { name => $key, value => $app->param( $key ) } );
        }
    } else {
        push ( @query_params, { name => 'mode', value => $mode } );
        if ( my $blog_id = $app->param( 'blog_id' ) ) {
            push ( @query_params, { key => 'blog_id', value => $blog_id } );
        }
        if ( my $return_url = $app->param( 'return_url' ) ) {
            push ( @query_params, { key => 'return_url', value => $return_url } );
        }
    }
    $params->{ query_params } = \@query_params;
    require MT::Auth;
    $app->{ plugin_template_path } = File::Spec->catdir( $component->path, 'tmpl' );
    return $app->build_page(
        'login.tmpl',
        { error                => $message,
          no_breadcrumbs       => 1,
          login_fields         => MT::Auth->login_form( $app ),
          can_recover_password => MT::Auth->can_recover_password,
          delegate_auth        => MT::Auth->delegate_auth,
          %$params,
        }
    );
}

sub _login_tmpl {
    my ( $cb, $app, $tmpl ) = @_;
    my $component = MT->component( 'RequiresLogin' );
    my $fmgr = MT::FileMgr->new( 'Local' ) or die MT::FileMgr->errstr;
    my $template = File::Spec->catdir( $component->path, 'tmpl', 'login.tmpl' );
    my $data = $fmgr->get_data( $template );
    $$tmpl = $data;
}

sub _error_tmpl {
    my ( $cb, $app, $tmpl ) = @_;
    my $component = MT->component( 'RequiresLogin' );
    my $fmgr = MT::FileMgr->new( 'Local' ) or die MT::FileMgr->errstr;
    my $template = File::Spec->catdir( $component->path, 'tmpl', 'error.tmpl' );
    my $data = $fmgr->get_data( $template );
    $$tmpl = $data;
}

sub save_profile {
    my $app = shift;
    my $registration = MT->config( 'RequiresLoginRegistration' )
        or $app->handle_error( $app->translate( 'Signing up is not allowed.' ) );
    # $app->{ template_dir } = 'comment';
    my $author = $app->user;
    $app->run_callbacks( 'members_pre_save.profile', $app, \$author );
    if ( $app->run_callbacks( 'api_save_filter.author', $app ) ) {
        # TODO;
    }
    require MT::App::Comments;
    MT::App::Comments::save_commenter_profile( $app );
    $app->run_callbacks( 'members_post_save.profile', $app, $author );
    # Alias for Members Plugin of PowerCMS
}

1;