"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.createScaffoldMiddleware = void 0;
/**
 * Creates a middleware function from an object of RPC method handler functions,
 * keyed to particular method names. If a method corresponding to a key of this
 * object is requested, this middleware will pass it to the corresponding
 * handler and return the result.
 *
 * @param handlers - The RPC method handler functions.
 * @returns The scaffold middleware function.
 */
function createScaffoldMiddleware(handlers) {
    return ({ request, context, next }) => {
        const handlerOrResult = handlers[request.method];
        if (handlerOrResult === undefined) {
            return next();
        }
        return typeof handlerOrResult === 'function'
            ? handlerOrResult({ request, context, next })
            : handlerOrResult;
    };
}
exports.createScaffoldMiddleware = createScaffoldMiddleware;
//# sourceMappingURL=createScaffoldMiddleware.cjs.map