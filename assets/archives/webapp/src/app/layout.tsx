import type { Metadata } from 'next'
import { Inter } from 'next/font/google'
import './globals.css'

const inter = Inter({ subsets: ['latin'] })

export const metadata: Metadata = {
  title: 'Azure Local E-commerce Demo',
  description: 'Simplified E-commerce application running on Azure Local',
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="en">
      <body className={inter.className}>
        <header className="bg-blue-600 text-white shadow-lg">
          <div className="container mx-auto px-4 py-4">
            <h1 className="text-2xl font-bold">Azure Local E-commerce Demo</h1>
            <p className="text-blue-100">Simplified full-stack web application</p>
          </div>
        </header>
        <main className="min-h-screen bg-gray-50">
          {children}
        </main>
        <footer className="bg-gray-800 text-white py-8">
          <div className="container mx-auto px-4 text-center">
            <p>&copy; 2024 Azure Local E-commerce Demo. Built with Next.js and PostgreSQL.</p>
          </div>
        </footer>
      </body>
    </html>
  )
}