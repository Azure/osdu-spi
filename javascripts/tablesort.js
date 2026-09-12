/* OSDU SPI Fork Management Interactive Features */

// Initialize Mermaid
document.addEventListener('DOMContentLoaded', function() {
    if (typeof mermaid !== 'undefined') {
        mermaid.initialize({
            startOnLoad: true,
            theme: 'default',
            themeVariables: {
                primaryColor: '#1976d2',
                primaryTextColor: '#fff',
                primaryBorderColor: '#1565c0',
                lineColor: '#757575'
            }
        });
    }
});

document$.subscribe(function() {
    // Table sorting functionality
    var tables = document.querySelectorAll("article table:not([class])")
    tables.forEach(function(table) {
        new Tablesort(table)
    })

    // Add copy buttons to code blocks
    var codeBlocks = document.querySelectorAll('pre > code')
    codeBlocks.forEach(function(codeBlock) {
        var pre = codeBlock.parentNode
        if (!pre.querySelector('.copy-button')) {
            var button = document.createElement('button')
            button.className = 'copy-button'
            button.innerHTML = '📋'
            button.title = 'Copy to clipboard'
            button.onclick = function() {
                navigator.clipboard.writeText(codeBlock.textContent).then(function() {
                    button.innerHTML = '✅'
                    setTimeout(function() {
                        button.innerHTML = '📋'
                    }, 2000)
                })
            }
            pre.style.position = 'relative'
            button.style.position = 'absolute'
            button.style.top = '8px'
            button.style.right = '8px'
            button.style.background = 'rgba(255, 255, 255, 0.8)'
            button.style.border = 'none'
            button.style.borderRadius = '4px'
            button.style.padding = '4px 8px'
            button.style.cursor = 'pointer'
            button.style.fontSize = '12px'
            pre.appendChild(button)
        }
    })

    // ADR status indicator enhancements
    var adrStatuses = document.querySelectorAll('.adr-status')
    adrStatuses.forEach(function(status) {
        var text = status.textContent.toLowerCase()
        if (text.includes('accepted')) {
            status.classList.add('accepted')
        } else if (text.includes('proposed')) {
            status.classList.add('proposed')
        } else if (text.includes('deprecated')) {
            status.classList.add('deprecated')
        }
    })

    // Workflow status indicators
    var workflowElements = document.querySelectorAll('.workflow-status')
    workflowElements.forEach(function(element) {
        var icon = document.createElement('span')
        icon.className = 'material-icons'
        var text = element.textContent.toLowerCase()
        
        if (text.includes('active') || text.includes('running')) {
            icon.textContent = 'play_circle'
            icon.style.color = '#4caf50'
        } else if (text.includes('pending') || text.includes('waiting')) {
            icon.textContent = 'schedule'
            icon.style.color = '#ff9800'
        } else if (text.includes('failed') || text.includes('error')) {
            icon.textContent = 'error'
            icon.style.color = '#f44336'
        } else if (text.includes('completed') || text.includes('success')) {
            icon.textContent = 'check_circle'
            icon.style.color = '#4caf50'
        } else {
            icon.textContent = 'info'
            icon.style.color = '#2196f3'
        }
        
        element.insertBefore(icon, element.firstChild)
    })

    // Smooth scroll for anchor links
    var anchorLinks = document.querySelectorAll('a[href^="#"]')
    anchorLinks.forEach(function(link) {
        link.addEventListener('click', function(e) {
            var target = document.querySelector(this.getAttribute('href'))
            if (target) {
                e.preventDefault()
                target.scrollIntoView({
                    behavior: 'smooth',
                    block: 'start'
                })
            }
        })
    })

    // Enhanced mermaid diagram handling
    var mermaidDiagrams = document.querySelectorAll('.mermaid')
    mermaidDiagrams.forEach(function(diagram) {
        diagram.style.backgroundColor = 'transparent'
        diagram.style.border = '1px solid rgba(0, 0, 0, 0.1)'
        diagram.style.borderRadius = '8px'
        diagram.style.padding = '16px'
        diagram.style.margin = '16px 0'
    })

    // Table enhancement for better mobile experience
    var tables = document.querySelectorAll('table:not([class])')
    tables.forEach(function(table) {
        // Add responsive wrapper
        if (!table.parentNode.classList.contains('table-responsive')) {
            var wrapper = document.createElement('div')
            wrapper.className = 'table-responsive'
            wrapper.style.overflowX = 'auto'
            wrapper.style.marginBottom = '1rem'
            table.parentNode.insertBefore(wrapper, table)
            wrapper.appendChild(table)
        }

        // Add sortable indicators to headers
        var headers = table.querySelectorAll('th')
        headers.forEach(function(header) {
            if (!header.querySelector('.sort-indicator')) {
                var indicator = document.createElement('span')
                indicator.className = 'sort-indicator'
                indicator.innerHTML = ' ↕️'
                indicator.style.opacity = '0.5'
                header.appendChild(indicator)
            }
        })
    })

    // Add keyboard navigation for better accessibility
    document.addEventListener('keydown', function(e) {
        // Alt + Home: Go to top of page
        if (e.altKey && e.key === 'Home') {
            window.scrollTo({ top: 0, behavior: 'smooth' })
        }
        
        // Alt + End: Go to bottom of page
        if (e.altKey && e.key === 'End') {
            window.scrollTo({ top: document.body.scrollHeight, behavior: 'smooth' })
        }
    })
})