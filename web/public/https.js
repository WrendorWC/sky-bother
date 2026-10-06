// Location, IDs and offline storage need a secure page; plain http
// (a typed address without https) broke both on an iPhone. A file of its
// own, not inline, so the Content-Security-Policy (_headers) can forbid
// inline scripts. Loaded first and blocking, as the inline one was.
if (location.protocol === 'http:' && location.hostname !== 'localhost') {
  location.replace('https://' + location.host + location.pathname + location.search + location.hash);
}
