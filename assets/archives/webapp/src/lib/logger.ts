import { createLogger, format, transports } from 'winston';

const { combine, timestamp, errors, json, colorize, simple } = format;

// Create the logger instance
export const logger = createLogger({
  level: process.env.NODE_ENV === 'production' ? 'info' : 'debug',
  format: combine(
    timestamp({ format: 'YYYY-MM-DD HH:mm:ss' }),
    errors({ stack: true }),
    json()
  ),
  defaultMeta: { service: 'ecommerce-webapp' },
  transports: [
    // Write to all logs with level `info` and below to combined.log
    new transports.File({ 
      filename: '/var/log/webapp/error.log', 
      level: 'error',
      handleExceptions: true,
      handleRejections: true
    }),
    new transports.File({ 
      filename: '/var/log/webapp/combined.log',
      handleExceptions: true,
      handleRejections: true
    }),
  ],
});

// If we're not in production then also log to the console
if (process.env.NODE_ENV !== 'production') {
  logger.add(new transports.Console({
    format: combine(
      colorize(),
      simple()
    ),
    handleExceptions: true,
    handleRejections: true
  }));
}

// Handle uncaught exceptions
logger.exceptions.handle(
  new transports.File({ filename: '/var/log/webapp/exceptions.log' })
);

// Handle unhandled rejections
logger.rejections.handle(
  new transports.File({ filename: '/var/log/webapp/rejections.log' })
);

export default logger;