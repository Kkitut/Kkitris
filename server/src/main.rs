// TODO: tokio UdpSocket transport
// TODO: quinn (QUIC: rustls encrypt + reliable streams + unreliable datagrams)
// TODO: rcgen dev certs, real certs in prod
// TODO: snow Noise path if custom UDP instead of quinn
// TODO: bincode packets, match net/proto.zig wire types
// TODO: packet loss: seq/ack bitfield, input redundancy, snapshots, StateHash desync check
// TODO: rooms/players in dashmap, uuid session ids
// TODO: clap args (port, tick rate), tracing logs

fn main() {}
