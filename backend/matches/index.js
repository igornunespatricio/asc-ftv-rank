exports.handler = async (event) => {
    return {
        statusCode: 200,
        body: JSON.stringify({
            message: "matches Lambda not yet implemented",
            method: event.requestContext.http.method,
            path: event.requestContext.http.path,
        }),
    };
};