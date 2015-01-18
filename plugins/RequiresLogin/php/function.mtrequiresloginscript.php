<?php
function smarty_function_mtrequiresloginscript ( $args, &$ctx ) {
    $app = $ctx->stash( 'bootstrapper' );
    if (! $app ) {
        $app = $ctx->mt;
    }
    $script = $app->config( 'RequiresLoginScript' );
    if ( $script ) return $script;
    return 'mt-requireslogin.cgi';
}
?>