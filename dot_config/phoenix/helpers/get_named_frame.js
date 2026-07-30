
/* GET NAMED FRAME */

function getNamedFrame ( name ) {

  const dTop = ( TOP_HEIGHT_PERCENTAGE - 50 ) / 100;
  const dLeft = ( LEFT_WIDTH_PERCENTAGE - 50 ) / 100;

  switch ( name ) {
    /* SIDES */
    case 'top': return [0, 0, 1, .5 + dTop];
    case 'right': return [.5 + dLeft, 0, .5 - dLeft, 1];
    case 'bottom': return [0, .5 + dTop, 1, .5 - dTop];
    case 'left': return [0, 0, .5 + dLeft, 1];
    /* CORNERS */
    case 'top-left': return [0, 0, .5 + dLeft, .5 + dTop];
    case 'top-right': return [.5 + dLeft, 0, .5 - dLeft, .5 + dTop];
    case 'bottom-right': return [.5 + dLeft, .5 + dTop, .5 - dLeft, .5 - dTop];
    case 'bottom-left': return [0, .5 + dTop, .5 + dLeft, .5 - dTop];
    /* HALVES */
    case 'half-1': return [0/2, 0, 1/2, 1];
    case 'half-2': return [1/2, 0, 1/2, 1];
    case 'left-half': return [0/2, 0, 1/2, 1];
    case 'right-half': return [1/2, 0, 1/2, 1];

    /* THIRDS */
    case 'third-1': return [0/3, 0, 1/3, 1];
    case 'third-2': return [1/3, 0, 1/3, 1];
    case 'third-3': return [2/3, 0, 1/3, 1];
    /* SIXTHS */
    case 'sixths-1': return [0/3, 0, 1/3, 1/2];
    case 'sixths-2': return [1/3, 0, 1/3, 1/2];
    case 'sixths-3': return [2/3, 0, 1/3, 1/2];
    case 'sixths-4': return [0/3, 1/2, 1/3, 1/2];
    case 'sixths-5': return [1/3, 1/2, 1/3, 1/2];
    case 'sixths-6': return [2/3, 1/2, 1/3, 1/2];

    case 'right-2/3': return [1/3, 0, 2/3, 1];
    case 'left-2/3': return [0, 0, 2/3, 1];

    /* LG */
    case 'lg1': return [0, 0, 1/5, 1];
    case 'lg2': return [1/5, 0, 1/3, 1];
    case 'lg3': return [1/5+1/3, 0, 1/3, 1];
    case 'lg4': return [1/5+2/3, 0, 2/15, 1/2];
    case 'lg5': return [1/5+2/3, 1/2, 2/15, 1/2];
    case 'lg6': return [1/5+2/3, 0, 2/15, 1];
    case 'lg7': return [0, 0, 2/15, 1/2];
    case 'lg8': return [0, 1/2, 2/15, 1/2];
    case 'lg9': return [0, 0, 2/15, 1];
    case 'lg10': return [2/15, 0, 1/3, 1];
    case 'lg11': return [2/15+1/3, 0, 1/3, 1];
    case 'lg12': return [2/15+2/3, 0, 1/5, 1];
    case 'lg13': return [1/3, 0, 2/3, 1];

    /* DEFAULT */
    default: throw new Error ( `Undefined frame named: "${name}"` );
  }

}
