
/* SET KEY HANDLER */

function setKeyHandler ( key, modifier, handler, handlerArgs = [], skipRepetitions = true, one = false ) {
  //Phoenix.log(`Setting key handler for ${key} with modifier ${modifier}`);
  Key[one ? 'once' : 'on']( key, modifier, ( identifier, repeated ) => {

    if ( repeated && skipRepetitions ) return;

    handler ( ...handlerArgs );

  });

}