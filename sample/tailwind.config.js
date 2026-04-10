/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    "./app/views/**/*.{erb,haml,html,rb}",
    "./app/components/**/*.rb",
    "./app/helpers/**/*.rb"
  ],
  theme: {
    extend: {
      colors: {
        brand: "#FF6600",
        "brand-dark": "#CC4F00"
      },
      fontFamily: {
        display: ["Inter", "system-ui", "sans-serif"]
      }
    }
  },
  plugins: [
    require("@tailwindcss/typography"),
    require("daisyui")
  ],
  daisyui: {
    themes: [
      "light",
      "dark",
      "cupcake",
      "corporate",
      {
        "phlexed-brand": {
          "primary":           "#FF6600",
          "primary-content":   "#FFFFFF",
          "secondary":         "#1F2937",
          "secondary-content": "#FFFFFF",
          "accent":            "#10B981",
          "accent-content":    "#FFFFFF",
          "neutral":           "#1F2937",
          "neutral-content":   "#F9FAFB",
          "base-100":          "#FFFFFF",
          "base-200":          "#F3F4F6",
          "base-300":          "#E5E7EB",
          "base-content":      "#1F2937",
          "info":              "#3B82F6",
          "info-content":      "#FFFFFF",
          "success":           "#10B981",
          "success-content":   "#FFFFFF",
          "warning":           "#F59E0B",
          "warning-content":   "#1F2937",
          "error":             "#EF4444",
          "error-content":     "#FFFFFF"
        }
      }
    ],
    darkTheme: "dark"
  }
}
