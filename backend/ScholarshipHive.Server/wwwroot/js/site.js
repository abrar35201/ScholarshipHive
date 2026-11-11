// Please see documentation at https://learn.microsoft.com/aspnet/core/client-side/bundling-and-minification
// for details on configuring this project to bundle and minify static web assets.

// Write your JavaScript code.

// Adds a Show/Hide toggle to every password field site-wide (login, user
// create/edit, change password, etc.) without needing each view to build
// its own — new password fields get this automatically too.
document.addEventListener('DOMContentLoaded', function () {
    var menuButton = document.querySelector('.menu-toggle');
    var sidebar = document.querySelector('.sidebar');
    var backdrop = document.querySelector('.sidebar-backdrop');

    if (menuButton && sidebar && backdrop) {
        function setMenuOpen(open) {
            sidebar.classList.toggle('is-open', open);
            backdrop.hidden = !open;
            menuButton.setAttribute('aria-expanded', String(open));
            menuButton.setAttribute('aria-label', open ? 'Close navigation menu' : 'Open navigation menu');
            document.body.classList.toggle('sidebar-open', open);
        }

        menuButton.addEventListener('click', function () {
            setMenuOpen(!sidebar.classList.contains('is-open'));
        });
        backdrop.addEventListener('click', function () { setMenuOpen(false); });
        sidebar.querySelectorAll('a').forEach(function (link) {
            link.addEventListener('click', function () { setMenuOpen(false); });
        });
        document.addEventListener('keydown', function (event) {
            if (event.key === 'Escape') setMenuOpen(false);
        });
        window.addEventListener('resize', function () {
            if (window.innerWidth > 900) setMenuOpen(false);
        });
    }

    // Wide data tables remain available and scroll within the page instead of
    // forcing the entire dashboard to overflow on narrow screens.
    document.querySelectorAll('.view-body table').forEach(function (table) {
        if (table.closest('.table-responsive')) return;
        var wrapper = document.createElement('div');
        wrapper.className = 'table-responsive';
        table.parentNode.insertBefore(wrapper, table);
        wrapper.appendChild(table);
    });

    document.querySelectorAll('input[type="password"]').forEach(function (input) {
        if (input.dataset.toggleAdded) return;
        input.dataset.toggleAdded = 'true';

        var wrapper = document.createElement('div');
        wrapper.style.position = 'relative';
        wrapper.style.width = '100%';
        input.parentNode.insertBefore(wrapper, input);
        wrapper.appendChild(input);
        input.style.paddingRight = '56px';

        var toggle = document.createElement('button');
        toggle.type = 'button';
        toggle.textContent = 'Show';
        toggle.setAttribute('aria-label', 'Show password');
        toggle.style.position = 'absolute';
        toggle.style.right = '8px';
        toggle.style.top = '50%';
        toggle.style.transform = 'translateY(-50%)';
        toggle.style.border = 'none';
        toggle.style.background = 'none';
        toggle.style.fontSize = '13px';
        toggle.style.color = '#0F4C81';
        toggle.style.cursor = 'pointer';
        toggle.addEventListener('click', function () {
            var isPassword = input.type === 'password';
            input.type = isPassword ? 'text' : 'password';
            toggle.textContent = isPassword ? 'Hide' : 'Show';
            toggle.setAttribute('aria-label', isPassword ? 'Hide password' : 'Show password');
        });
        wrapper.appendChild(toggle);
    });
});
