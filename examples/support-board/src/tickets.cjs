function teamTickets(tickets) {
    return tickets.filter(ticket => ticket.visibility === 'team');
}

function summarize(tickets) {
    const counts = { open: 0, closed: 0 };
    for (const ticket of teamTickets(tickets)) {
        if (ticket.status === 'open' || ticket.status === 'closed') counts[ticket.status]++;
    }
    return counts;
}

module.exports = { teamTickets, summarize };
