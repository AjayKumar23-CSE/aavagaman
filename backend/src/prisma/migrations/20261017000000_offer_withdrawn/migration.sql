-- Broadcast matching (D-055): an offer that loses to another driver, or that a driver gives
-- up by accepting a different ride, is closed as "withdrawn" (timeout/rejected keep their meaning).
ALTER TYPE "offer_response" ADD VALUE 'withdrawn';
