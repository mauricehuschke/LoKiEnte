function teamTickets(tickets) {
    return tickets.filter(ticket => ticket.visibility === 'team');
}

module.exports = { teamTickets };
